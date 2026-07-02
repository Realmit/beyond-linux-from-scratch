#!/bin/bash
set -e

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
# 1. Copier les sources
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
# 2. Copier tous les outils et leurs bibliothèques
# ============================================================================
ensure_tools_in_chroot() {
    # Liste des commandes indispensables (incluant xz)
    local tools=(
        "bash" "tar" "make" "gcc" "g++" "ld" "ar" "nm" "strip"
        "gawk" "sed" "grep" "find" "xargs" "cp" "mv" "rm" "mkdir"
        "ln" "chmod" "chown" "cat" "echo" "pwd" "which" "m4"
        "bison" "flex" "xz"   # <--- AJOUT DE xz
    )

    mkdir -p "$LFS/bin" "$LFS/usr/bin" "$LFS/lib" "$LFS/lib64" "$LFS/usr/lib" "$LFS/usr/lib64"

    # Copier un binaire et toutes ses bibliothèques
    copy_binary() {
        local bin="$1"
        local src=$(which "$bin" 2>/dev/null)
        [ -z "$src" ] && return 1
        local dest="$LFS/bin/$(basename "$src")"
        if [ ! -x "$dest" ]; then
            cp -L "$src" "$dest"
            chmod 755 "$dest"
            log_info "Copied $bin -> $dest"
        fi
        # Copier les bibliothèques
        ldd "$src" 2>/dev/null | grep "=>" | awk '{print $3}' | while read lib; do
            [ -z "$lib" ] || [ ! -f "$lib" ] && continue
            local lib_dest="$LFS/lib64/$(basename "$lib")"
            if [[ "$lib" == /lib/* ]]; then
                lib_dest="$LFS/lib/$(basename "$lib")"
            elif [[ "$lib" == /usr/lib/* ]]; then
                lib_dest="$LFS/usr/lib/$(basename "$lib")"
            fi
            if [ ! -f "$lib_dest" ]; then
                mkdir -p "$(dirname "$lib_dest")"
                cp -L "$lib" "$lib_dest"
                chmod 755 "$lib_dest"
                log_info "  Library: $(basename "$lib")"
            fi
        done
        # Copier également les liens dans /lib et /usr/lib
        if [ -L "$src" ]; then
            local link_target=$(readlink -f "$src")
            if [ -f "$link_target" ]; then
                cp -L "$link_target" "$dest" 2>/dev/null || true
            fi
        fi
        return 0
    }

    for tool in "${tools[@]}"; do
        copy_binary "$tool" || log_warning "Binary '$tool' not found"
    done

    # Copier ld-linux (interpréteur dynamique)
    LD_TARGET="$LFS/lib64/ld-linux-x86-64.so.2"
    if [ ! -f "$LD_TARGET" ] || [ -L "$LD_TARGET" ]; then
        [ -L "$LD_TARGET" ] && rm -f "$LD_TARGET"
        LD_SRC=$(ldd /bin/bash | grep -E 'ld-linux|ld-2' | awk '{print $3}')
        [ -z "$LD_SRC" ] && LD_SRC="/lib64/ld-linux-x86-64.so.2"
        if [ -f "$LD_SRC" ]; then
            cp -L "$LD_SRC" "$LD_TARGET"
            chmod 755 "$LD_TARGET"
            log_info "Copied ld-linux"
        else
            log_error "ld-linux not found"
            exit 1
        fi
    fi

    # Créer les liens /usr/bin -> /bin et /usr/lib -> /lib
    for tool in "${tools[@]}"; do
        local base=$(basename "$(which "$tool" 2>/dev/null || echo "")")
        if [ -n "$base" ] && [ -x "$LFS/bin/$base" ] && [ ! -x "$LFS/usr/bin/$base" ]; then
            ln -sf ../bin/"$base" "$LFS/usr/bin/$base"
        fi
    done
    [ ! -e "$LFS/usr/lib" ] && ln -sf ../lib "$LFS/usr/lib"
    [ ! -e "$LFS/usr/lib64" ] && ln -sf ../lib64 "$LFS/usr/lib64"

    # Copier les bibliothèques système manquantes (libc, libm, etc.)
    for lib in libc.so.6 libm.so.6 libdl.so.2 libpthread.so.0; do
        find /lib /lib64 /usr/lib /usr/lib64 -name "$lib" 2>/dev/null | while read src; do
            dest="$LFS/lib64/$(basename "$src")"
            if [[ "$src" == /lib/* ]]; then
                dest="$LFS/lib/$(basename "$src")"
            elif [[ "$src" == /usr/lib/* ]]; then
                dest="$LFS/usr/lib/$(basename "$src")"
            fi
            [ ! -f "$dest" ] && { cp -L "$src" "$dest"; chmod 755 "$dest"; log_info "Copied $lib"; }
        done
    done

    # Tester rapidement gcc
    log_info "Testing chroot with gcc --version"
    if chroot "$LFS" /bin/bash -c "gcc --version" >/dev/null 2>&1; then
        log_success "gcc works in chroot"
    else
        log_error "gcc test failed – missing libraries"
        log_info "Contents of /lib64 in chroot:"
        ls -la "$LFS/lib64" || true
        exit 1
    fi

    # Vérifier que xz est disponible
    if chroot "$LFS" /bin/bash -c "xz --version" >/dev/null 2>&1; then
        log_success "xz works in chroot"
    else
        log_warning "xz not available in chroot – tar may fail with .xz archives"
    fi
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
# 4. Compilation du noyau
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