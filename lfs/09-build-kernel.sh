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

# Détection architecture
if [ -n "$ARCH" ]; then
    TARGET_ARCH="$ARCH"
elif [ -n "$LFS_TGT" ]; then
    TARGET_ARCH=$(echo "$LFS_TGT" | cut -d- -f1)
else
    TARGET_ARCH="$(uname -m)"
fi
log_info "Target architecture: $TARGET_ARCH"
case "$TARGET_ARCH" in
    x86_64|amd64)  MAKE_ARCH="x86_64" ;;
    aarch64|arm64) MAKE_ARCH="arm64" ;;
    armv7l|armhf)  MAKE_ARCH="arm" ;;
    riscv64)       MAKE_ARCH="riscv" ;;
    *)             MAKE_ARCH="$TARGET_ARCH" ;;
esac

# S'assurer que les sources sont disponibles
SOURCES_HOST="$(dirname "$LFS")/sources"
if [ ! -d "$LFS/sources" ] || [ -z "$(ls -A "$LFS/sources" 2>/dev/null)" ]; then
    if [ -d "$SOURCES_HOST" ] && [ -n "$(ls -A "$SOURCES_HOST" 2>/dev/null)" ]; then
        log_info "Copying sources from $SOURCES_HOST to $LFS/sources"
        mkdir -p "$LFS/sources"
        cp -rv "$SOURCES_HOST"/* "$LFS/sources/"
        chown -R lfs:lfs "$LFS/sources" 2>/dev/null || true
    else
        log_error "No sources found"
        exit 1
    fi
fi

# Trouver l'archive du noyau sur l'hôte
cd "$LFS/sources"
KERNEL_ARCHIVE=$(ls -1 "${KERNEL_TYPE}"-*.tar.xz 2>/dev/null | head -n1)
if [ -z "$KERNEL_ARCHIVE" ]; then
    log_error "No kernel source found for type: $KERNEL_TYPE"
    exit 1
fi
log_info "Using kernel source: $KERNEL_ARCHIVE"

if [ -f "$LFS/boot/vmlinuz" ]; then
    log_info "Kernel already installed – skipping"
    exit 0
fi

# Extraire le noyau sur l'hôte (dans un répertoire temporaire)
WORKDIR=$(mktemp -d)
log_info "Extracting kernel source on host to $WORKDIR"
tar -xf "$LFS/sources/$KERNEL_ARCHIVE" -C "$WORKDIR"
KERNEL_DIR=$(tar -tf "$LFS/sources/$KERNEL_ARCHIVE" | head -1 | cut -d/ -f1)
EXTRACTED_KERNEL="$WORKDIR/$KERNEL_DIR"
log_info "Kernel extracted to $EXTRACTED_KERNEL"

# Copier le répertoire extrait dans $LFS/sources (pour que le chroot y ait accès)
KERNEL_BUILD_DIR="$LFS/sources/kernel-build"
rm -rf "$KERNEL_BUILD_DIR"
mkdir -p "$KERNEL_BUILD_DIR"
cp -rv "$EXTRACTED_KERNEL"/* "$KERNEL_BUILD_DIR/"
chown -R lfs:lfs "$KERNEL_BUILD_DIR" 2>/dev/null || true

# Copier dans le chroot les outils nécessaires : bash, make, gcc (pas tar, pas xz)
mkdir -p "$LFS/bin" "$LFS/usr/bin" "$LFS/lib" "$LFS/lib64" "$LFS/usr/lib" "$LFS/usr/lib64"

copy_binary() {
    local src="$1"
    local dest="$2"
    if [ ! -f "$dest" ]; then
        cp -L "$src" "$dest"
        chmod 755 "$dest"
        log_info "Copied $(basename "$src")"
    fi
}

copy_libs() {
    local bin="$1"
    ldd "$bin" 2>/dev/null | grep "=>" | awk '{print $3}' | while read lib; do
        [ -z "$lib" ] || [ ! -f "$lib" ] && continue
        local dest_dir="$LFS/lib64"
        [[ "$lib" == /lib/* ]] && dest_dir="$LFS/lib"
        [[ "$lib" == /usr/lib/* ]] && dest_dir="$LFS/usr/lib"
        mkdir -p "$dest_dir"
        local dest="$dest_dir/$(basename "$lib")"
        [ ! -f "$dest" ] && { cp -L "$lib" "$dest"; chmod 755 "$dest"; }
    done
}

for tool in bash make gcc; do
    src=$(which "$tool" 2>/dev/null || echo "")
    [ -z "$src" ] && { log_error "$tool not found on host"; exit 1; }
    dest="$LFS/bin/$(basename "$src")"
    if [ ! -x "$dest" ]; then
        copy_binary "$src" "$dest"
        copy_libs "$src"
    fi
done

# Copier ld-linux (interpréteur dynamique) si absent
LD_TARGET="$LFS/lib64/ld-linux-x86-64.so.2"
if [ ! -f "$LD_TARGET" ] && [ ! -f "$LFS/lib/ld-linux.so.2" ]; then
    LD_SRC=$(ldd /bin/bash | grep -E 'ld-linux|ld-2' | awk '{print $3}')
    [ -z "$LD_SRC" ] && LD_SRC="/lib64/ld-linux-x86-64.so.2"
    if [ -f "$LD_SRC" ]; then
        mkdir -p "$LFS/lib64"
        cp -L "$LD_SRC" "$LD_TARGET"
        chmod 755 "$LD_TARGET"
        log_info "Copied ld-linux"
    fi
fi

# Créer les liens /usr/bin -> /bin
for tool in bash make gcc; do
    [ -x "$LFS/bin/$(basename "$(which "$tool" 2>/dev/null || echo "")")" ] && \
    [ ! -x "$LFS/usr/bin/$(basename "$tool")" ] && \
    ln -sf ../bin/$(basename "$tool") "$LFS/usr/bin/$(basename "$tool")"
done

# Monter les FS virtuels
mountpoint -q "$LFS/dev"  || mount --bind /dev "$LFS/dev"
mountpoint -q "$LFS/dev/pts" || mount -t devpts devpts "$LFS/dev/pts"
mountpoint -q "$LFS/proc" || mount -t proc proc "$LFS/proc"
mountpoint -q "$LFS/sys"  || mount -t sysfs sysfs "$LFS/sys"

cleanup() {
    umount "$LFS/dev/pts" 2>/dev/null || true
    umount "$LFS/dev" 2>/dev/null || true
    umount "$LFS/proc" 2>/dev/null || true
    umount "$LFS/sys" 2>/dev/null || true
    rm -rf "$WORKDIR" 2>/dev/null || true
}
trap cleanup EXIT

# Lancer la compilation dans le chroot
chroot "$LFS" /bin/bash << EOF
set -e
export CC=gcc
export HOSTCC=gcc
export CXX=g++
export HOSTCXX=g++

cd /sources/kernel-build
make ARCH="$MAKE_ARCH" mrproper
make ARCH="$MAKE_ARCH" defconfig
make ARCH="$MAKE_ARCH" -j\$(nproc)
make ARCH="$MAKE_ARCH" modules_install

mkdir -p /boot
if [ -f arch/$MAKE_ARCH/boot/bzImage ]; then
    cp arch/$MAKE_ARCH/boot/bzImage /boot/vmlinuz
elif [ -f arch/$MAKE_ARCH/boot/Image ]; then
    cp arch/$MAKE_ARCH/boot/Image /boot/vmlinuz
elif [ -f vmlinuz ]; then
    cp vmlinuz /boot/vmlinuz
elif [ -f arch/$MAKE_ARCH/boot/zImage ]; then
    cp arch/$MAKE_ARCH/boot/zImage /boot/vmlinuz
else
    echo "ERROR: No kernel image found"
    exit 1
fi
cp System.map /boot/System.map

# Nettoyer les sources après compilation (optionnel)
rm -rf /sources/kernel-build
EOF

log_success "Kernel $KERNEL_TYPE compiled and installed to $LFS/boot/vmlinuz"