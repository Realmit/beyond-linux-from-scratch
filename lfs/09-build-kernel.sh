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
# Vérifier /bin/bash – le copier depuis l'hôte si absent
# ============================================================================
ensure_bash_in_chroot() {
    mkdir -p "$LFS/bin" "$LFS/lib" "$LFS/lib64"

    # 1. Copier bash s'il n'existe pas
    if [ ! -x "$LFS/bin/bash" ]; then
        BASH_SRC=$(which bash 2>/dev/null || echo "/bin/bash")
        [ ! -f "$BASH_SRC" ] && BASH_SRC="/usr/bin/bash"
        [ ! -f "$BASH_SRC" ] && { log_error "bash not found on host"; exit 1; }
        cp -L "$BASH_SRC" "$LFS/bin/bash"
        chmod 755 "$LFS/bin/bash"
        log_info "bash copied from $BASH_SRC"
    else
        log_info "bash already present in chroot"
    fi

    # 2. Copier ld-linux s'il n'existe pas
    LD_TARGET="$LFS/lib64/ld-linux-x86-64.so.2"
    if [ ! -f "$LD_TARGET" ]; then
        LD_SRC=$(ldd /bin/bash | grep -E 'ld-linux|ld-2' | awk '{print $3}')
        if [ -n "$LD_SRC" ] && [ -f "$LD_SRC" ]; then
            mkdir -p "$LFS/lib64"
            # Éviter la copie si source == destination
            if [ "$LD_SRC" != "$LD_TARGET" ]; then
                cp -L "$LD_SRC" "$LD_TARGET"
                chmod 755 "$LD_TARGET"
                log_info "ld-linux copied to $LD_TARGET"
            else
                log_info "ld-linux already in correct location"
            fi
        else
            # Recherche manuelle
            for ld in /lib64/ld-linux*.so.* /lib/ld-linux*.so.*; do
                if [ -f "$ld" ]; then
                    mkdir -p "$LFS/lib64"
                    if [ "$ld" != "$LD_TARGET" ]; then
                        cp -L "$ld" "$LD_TARGET"
                        chmod 755 "$LD_TARGET"
                        log_info "ld-linux copied from $ld"
                        break
                    fi
                fi
            done
        fi
    else
        log_info "ld-linux already present in chroot"
    fi

    # 3. Copier les bibliothèques partagées dont bash a besoin (si elles ne sont pas déjà présentes)
    ldd /bin/bash | grep "=>" | awk '{print $3}' | while read lib; do
        [ -z "$lib" ] && continue
        if [ -f "$lib" ]; then
            dest_dir="$LFS/lib64"
            if [[ "$lib" == /lib/* ]]; then
                dest_dir="$LFS/lib"
            elif [[ "$lib" == /usr/lib/* ]]; then
                dest_dir="$LFS/usr/lib"
            fi
            mkdir -p "$dest_dir"
            dest_file="$dest_dir/$(basename "$lib")"
            if [ ! -f "$dest_file" ] && [ "$lib" != "$dest_file" ]; then
                cp -L "$lib" "$dest_file"
                chmod 755 "$dest_file"
                log_info "copied library: $(basename "$lib")"
            fi
        fi
    done

    # 4. Créer un lien /lib64 -> /lib si nécessaire (certains binaires cherchent dans /lib64)
    if [ ! -e "$LFS/lib64/ld-linux-x86-64.so.2" ] && [ -e "$LFS/lib/ld-linux-x86-64.so.2" ]; then
        ln -sf ../lib/ld-linux-x86-64.so.2 "$LFS/lib64/ld-linux-x86-64.so.2"
    fi

    # 5. Tester le chroot
    log_info "Testing chroot..."
    if ! chroot "$LFS" /bin/bash -c "exit 0" 2>/dev/null; then
        log_error "chroot test failed – missing libraries"
        log_info "Contents of $LFS/bin:"
        ls -la "$LFS/bin" || true
        log_info "Contents of $LFS/lib64:"
        ls -la "$LFS/lib64" || true
        exit 1
    fi
    log_success "chroot works with /bin/bash"
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