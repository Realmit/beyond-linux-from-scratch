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
# 1. Copier les sources depuis l'hôte vers $LFS/sources
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
# 2. Copier tous les outils nécessaires (bash, tar, make, gcc, etc.)
# ============================================================================
ensure_tools_in_chroot() {
    # Liste des commandes requises
    local tools=("bash" "tar" "make" "gcc" "g++" "ld" "ar" "nm" "strip" "gawk" "sed" "grep" "find" "xargs" "cp" "mv" "rm" "mkdir" "ln" "chmod" "chown" "cat" "echo" "pwd" "which")

    mkdir -p "$LFS/bin" "$LFS/usr/bin" "$LFS/lib" "$LFS/lib64" "$LFS/usr/lib" "$LFS/usr/lib64"

    # Fonction pour copier un binaire et ses bibliothèques
    copy_binary() {
        local bin="$1"
        local src=$(which "$bin" 2>/dev/null || echo "")
        [ -z "$src" ] && { log_warning "Binary '$bin' not found on host"; return 1; }
        # Copier le binaire lui-même
        local dest="$LFS/bin/$(basename "$src")"
        if [ ! -x "$dest" ]; then
            cp -L "$src" "$dest"
            chmod 755 "$dest"
            log_info "Copied $bin -> $dest"
        fi
        # Copier toutes les bibliothèques dont ce binaire dépend
        ldd "$src" 2>/dev/null | grep "=>" | awk '{print $3}' | while read lib; do
            [ -z "$lib" ] && continue
            if [ -f "$lib" ]; then
                local lib_dest="$LFS/lib64/$(basename "$lib")"
                if [[ "$lib" == /lib/* ]]; then
                    lib_dest="$LFS/lib/$(basename "$lib")"
                elif [[ "$lib" == /usr/lib/* ]]; then
                    lib_dest="$LFS/usr/lib/$(basename "$lib")"
                fi
                if [ ! -f "$lib_dest" ] && [ "$lib" != "$lib_dest" ]; then
                    mkdir -p "$(dirname "$lib_dest")"
                    cp -L "$lib" "$lib_dest"
                    chmod 755 "$lib_dest"
                    log_info "Copied library: $(basename "$lib")"
                fi
            fi
        done
        return 0
    }

    # Copier tous les outils
    for tool in "${tools[@]}"; do
        copy_binary "$tool" || true
    done

    # Copier ld-linux (l'interpréteur dynamique) explicitement
    LD_TARGET="$LFS/lib64/ld-linux-x86-64.so.2"
    if [ ! -f "$LD_TARGET" ] || [ -L "$LD_TARGET" ]; then
        [ -L "$LD_TARGET" ] && rm -f "$LD_TARGET"
        LD_SRC=$(ldd /bin/bash | grep -E 'ld-linux|ld-2' | awk '{print $3}')
        [ -z "$LD_SRC" ] && LD_SRC="/lib64/ld-linux-x86-64.so.2"
        if [ -f "$LD_SRC" ]; then
            cp -L "$LD_SRC" "$LD_TARGET"
            chmod 755 "$LD_TARGET"
            log_info "Copied ld-linux to $LD_TARGET"
        else
            log_error "ld-linux not found"
            exit 1
        fi
    fi

    # Créer des liens symboliques pour /usr/bin -> /bin
    for tool in "${tools[@]}"; do
        if [ -x "$LFS/bin/$(basename "$(which "$tool" 2>/dev/null || echo "")")" ] && [ ! -x "$LFS/usr/bin/$(basename "$tool")" ]; then
            ln -sf ../bin/"$(basename "$tool")" "$LFS/usr/bin/$(basename "$tool")"
        fi
    done

    # Vérification : tester une compilation simple
    log_info "Testing chroot with a simple C compile"
    if ! chroot "$LFS" /bin/bash -c "echo 'int main(){}' | gcc -x c - -o /tmp/test && /tmp/test && rm /tmp/test" 2>/dev/null; then
        log_error "Chroot compilation test failed – missing tools or libraries"
        log_info "Contents of $LFS/bin:"
        ls -la "$LFS/bin" || true
        log_info "Contents of $LFS/lib64:"
        ls -la "$LFS/lib64" || true
        exit 1
    fi
    log_success "Chroot ready for compilation"
}

ensure_tools_in_chroot

# ============================================================================
# 3. Montages
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
# 4. Trouver l'archive du noyau
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
# 5. Compilation du noyau dans le chroot
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