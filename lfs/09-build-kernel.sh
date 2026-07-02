#!/bin/bash
set -e

# Se relancer avec sudo si nécessaire
if [ "$EUID" -ne 0 ]; then
    echo "[INFO] Relaunching with sudo..."
    exec sudo -E "$0" "$@"
fi

LFS=${LFS:-/mnt/lfs}
KERNEL_TYPE=${KERNEL_TYPE:-linux}

log_info() { echo "[INFO] $*"; }
log_error() { echo "[ERROR] $*" >&2; }
log_success() { echo "[SUCCESS] $*"; }

# ============================================================================
# Copier les sources si elles manquent
# ============================================================================
SOURCES_HOST="$(dirname "$LFS")/sources"
if [ ! -d "$LFS/sources" ] || [ -z "$(ls -A "$LFS/sources" 2>/dev/null)" ]; then
    if [ -d "$SOURCES_HOST" ] && [ -n "$(ls -A "$SOURCES_HOST" 2>/dev/null)" ]; then
        log_info "Copying sources from $SOURCES_HOST to $LFS/sources"
        mkdir -p "$LFS/sources"
        cp -rv "$SOURCES_HOST"/* "$LFS/sources/"
        chown -R lfs:lfs "$LFS/sources" 2>/dev/null || true
    else
        log_error "No sources found in $SOURCES_HOST and $LFS/sources is empty"
        exit 1
    fi
fi

# ============================================================================
# Copier bash et ses dépendances depuis l'hôte si absents du chroot
# ============================================================================
ensure_bash_in_chroot() {
    if [ -x "$LFS/bin/bash" ]; then
        log_info "bash already present in chroot"
        return 0
    fi

    log_info "bash not found in chroot – copying from host"
    mkdir -p "$LFS/bin" "$LFS/lib" "$LFS/lib64"

    # Copier bash lui-même
    BASH_SRC="/bin/bash"
    [ ! -f "$BASH_SRC" ] && BASH_SRC="/usr/bin/bash"
    [ ! -f "$BASH_SRC" ] && { log_error "bash not found on host"; exit 1; }
    cp -L "$BASH_SRC" "$LFS/bin/bash"
    chmod 755 "$LFS/bin/bash"

    # Copier ld-linux (le vrai fichier, pas le lien)
    LD_SRC=$(ldd /bin/bash | grep ld-linux | awk '{print $3}')
    if [ -n "$LD_SRC" ]; then
        LD_DEST="$LFS/lib64/$(basename $LD_SRC)"
        mkdir -p "$LFS/lib64"
        cp -L "$LD_SRC" "$LD_DEST"
        chmod 755 "$LD_DEST"
    else
        # Fallback: chercher ld-linux dans /lib64 ou /lib
        for ld in /lib64/ld-linux*.so.* /lib/ld-linux*.so.*; do
            if [ -f "$ld" ]; then
                mkdir -p "$LFS/lib64"
                cp -L "$ld" "$LFS/lib64/"
                chmod 755 "$LFS/lib64/$(basename "$ld")"
                break
            fi
        done
    fi

    # Copier les librairies partagées dont bash a besoin
    ldd /bin/bash | grep "=>" | awk '{print $3}' | while read lib; do
        if [ -n "$lib" ] && [ -f "$lib" ]; then
            dest_dir="$LFS/lib64"
            if [[ "$lib" == /lib/* ]]; then
                dest_dir="$LFS/lib"
            fi
            mkdir -p "$dest_dir"
            cp -L "$lib" "$dest_dir/"
            chmod 755 "$dest_dir/$(basename "$lib")"
        fi
    done

    # Vérifier que bash peut être exécuté (test de base)
    if ! chroot "$LFS" /bin/bash -c "exit 0" 2>/dev/null; then
        log_error "bash still not working in chroot – missing library?"
        exit 1
    fi
    log_success "bash and libraries copied successfully"
}

ensure_bash_in_chroot

# ============================================================================
# Montages
# ============================================================================
mountpoint -q "$LFS/dev"  || mount --bind /dev "$LFS/dev"
mountpoint -q "$LFS/dev/pts" || mount -t devpts devpts "$LFS/dev/pts"
mountpoint -q "$LFS/proc" || mount -t proc proc "$LFS/proc"
mountpoint -q "$LFS/sys"  || mount -t sysfs sysfs "$LFS/sys"

cleanup() {
    umount "$LFS/dev/pts" 2>/dev/null || true
    umount "$LFS/dev" 2>/dev/null || true
    umount "$LFS/proc" 2>/dev/null || true
    umount "$LFS/sys" 2>/dev/null || true
}
trap cleanup EXIT

# ============================================================================
# Trouver l'archive du noyau
# ============================================================================
cd "$LFS/sources"
KERNEL_ARCHIVE=$(ls -1 "${KERNEL_TYPE}"-*.tar.xz 2>/dev/null | head -n1)
if [ -z "$KERNEL_ARCHIVE" ]; then
    log_error "No kernel source found for type: $KERNEL_TYPE"
    exit 1
fi
log_info "Using kernel source: $KERNEL_ARCHIVE"

KERNEL_DIR=$(tar -tf "$KERNEL_ARCHIVE" | head -1 | cut -d/ -f1)
log_info "Kernel directory: $KERNEL_DIR"

if [ -f "$LFS/boot/vmlinuz" ]; then
    log_info "Kernel already installed – skipping"
    exit 0
fi

# ============================================================================
# Compilation
# ============================================================================
chroot "$LFS" /bin/bash << EOF
set -e
cd /sources
tar -xf "$KERNEL_ARCHIVE"
cd "$KERNEL_DIR"
make mrproper
make defconfig
make -j\$(nproc)
make modules_install
cp arch/x86/boot/bzImage /boot/vmlinuz
cp System.map /boot/System.map
cd /sources
rm -rf "$KERNEL_DIR"
EOF

log_success "Kernel $KERNEL_TYPE compiled and installed to $LFS/boot/vmlinuz"