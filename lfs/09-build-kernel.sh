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
# Détection de l'architecture cible
# ============================================================================
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

# ============================================================================
# Copie des sources si elles manquent dans $LFS/sources
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
# Trouver l'archive du noyau
# ============================================================================
cd "$LFS/sources"
KERNEL_ARCHIVE=$(ls -1 "${KERNEL_TYPE}"-*.tar.xz 2>/dev/null | head -n1)
if [ -z "$KERNEL_ARCHIVE" ]; then
    log_error "No kernel source found for type: $KERNEL_TYPE (pattern: ${KERNEL_TYPE}-*.tar.xz)"
    exit 1
fi
log_info "Using kernel source: $KERNEL_ARCHIVE"

# Si le noyau est déjà installé, on saute
if [ -f "$LFS/boot/vmlinuz" ]; then
    log_info "Kernel already installed – skipping"
    exit 0
fi

# ============================================================================
# Extraire le noyau sur l'hôte (car tar/xz peuvent manquer dans le chroot)
# ============================================================================
WORKDIR=$(mktemp -d)
log_info "Extracting kernel source on host to $WORKDIR"
tar -xf "$LFS/sources/$KERNEL_ARCHIVE" -C "$WORKDIR"
KERNEL_DIR=$(tar -tf "$LFS/sources/$KERNEL_ARCHIVE" | head -1 | cut -d/ -f1)
EXTRACTED_KERNEL="$WORKDIR/$KERNEL_DIR"
log_info "Kernel extracted to $EXTRACTED_KERNEL"

# Copier le répertoire extrait dans $LFS/sources pour le chroot
KERNEL_BUILD_DIR="$LFS/sources/kernel-build"
rm -rf "$KERNEL_BUILD_DIR"
mkdir -p "$KERNEL_BUILD_DIR"
cp -rv "$EXTRACTED_KERNEL"/* "$KERNEL_BUILD_DIR/"
chown -R lfs:lfs "$KERNEL_BUILD_DIR" 2>/dev/null || true

# ============================================================================
# BIND MOUNTS : donner accès aux outils de l'hôte
# ============================================================================
mkdir -p "$LFS/bin" "$LFS/usr/bin" "$LFS/lib" "$LFS/lib64" "$LFS/usr/lib" "$LFS/usr/lib64"

# Monter les répertoires de l'hôte (en lecture seule pour éviter les modifications)
mountpoint -q "$LFS/bin"  || mount --bind /bin "$LFS/bin"
mountpoint -q "$LFS/usr/bin" || mount --bind /usr/bin "$LFS/usr/bin"
mountpoint -q "$LFS/lib"  || mount --bind /lib "$LFS/lib"
mountpoint -q "$LFS/lib64" || mount --bind /lib64 "$LFS/lib64"
mountpoint -q "$LFS/usr/lib" || mount --bind /usr/lib "$LFS/usr/lib"

# Montages virtuels essentiels
mountpoint -q "$LFS/dev"  || mount --bind /dev "$LFS/dev"
mountpoint -q "$LFS/dev/pts" || mount -t devpts devpts "$LFS/dev/pts"
mountpoint -q "$LFS/proc" || mount -t proc proc "$LFS/proc"
mountpoint -q "$LFS/sys"  || mount -t sysfs sysfs "$LFS/sys"
mountpoint -q "$LFS/run"  || mount -t tmpfs tmpfs "$LFS/run"

# Nettoyage en fin de script
cleanup() {
    umount "$LFS/dev/pts" 2>/dev/null || true
    umount "$LFS/dev" 2>/dev/null || true
    umount "$LFS/proc" 2>/dev/null || true
    umount "$LFS/sys" 2>/dev/null || true
    umount "$LFS/run" 2>/dev/null || true
    umount "$LFS/bin" 2>/dev/null || true
    umount "$LFS/usr/bin" 2>/dev/null || true
    umount "$LFS/lib" 2>/dev/null || true
    umount "$LFS/lib64" 2>/dev/null || true
    umount "$LFS/usr/lib" 2>/dev/null || true
    rm -rf "$WORKDIR" 2>/dev/null || true
}
trap cleanup EXIT

# ============================================================================
# DIAGNOSTIC : Vérifier que les outils sont accessibles via le chroot
# ============================================================================
log_info "Checking chroot environment with bind mounts..."

# Vérifier /bin/bash
if chroot "$LFS" /bin/bash -c "exit 0" 2>/dev/null; then
    log_success "/bin/bash works in chroot"
else
    log_error "/bin/bash does not work in chroot"
    exit 1
fi

# Vérifier gcc
if chroot "$LFS" /bin/bash -c "gcc --version" >/dev/null 2>&1; then
    log_success "gcc found in chroot"
else
    log_error "gcc not found in chroot"
    exit 1
fi

# Vérifier make
if chroot "$LFS" /bin/bash -c "make --version" >/dev/null 2>&1; then
    log_success "make found in chroot"
else
    log_error "make not found in chroot"
    exit 1
fi

# ============================================================================
# Compilation dans le chroot avec environnement propre (env -i) et logs détaillés
# ============================================================================
log_info "Starting kernel compilation in chroot (architecture: $MAKE_ARCH)"
# On redirige la sortie d'erreur vers la sortie standard pour tout capturer
chroot "$LFS" /bin/bash -x << 'EOF' 2>&1
set -e
cd /sources/kernel-build

echo "=== Step 1: mrproper ==="
env -i PATH="/bin:/usr/bin" CC="gcc" HOSTCC="gcc" CXX="g++" HOSTCXX="g++" \
    make ARCH="$MAKE_ARCH" mrproper
echo "=== Step 1 done ==="

echo "=== Step 2: defconfig ==="
env -i PATH="/bin:/usr/bin" CC="gcc" HOSTCC="gcc" CXX="g++" HOSTCXX="g++" \
    make ARCH="$MAKE_ARCH" defconfig
echo "=== Step 2 done ==="

echo "=== Step 3: building kernel ==="
env -i PATH="/bin:/usr/bin" CC="gcc" HOSTCC="gcc" CXX="g++" HOSTCXX="g++" \
    make ARCH="$MAKE_ARCH" -j$(nproc)
echo "=== Step 3 done ==="

echo "=== Step 4: modules_install ==="
env -i PATH="/bin:/usr/bin" CC="gcc" HOSTCC="gcc" CXX="g++" HOSTCXX="g++" \
    make ARCH="$MAKE_ARCH" modules_install
echo "=== Step 4 done ==="

echo "=== Step 5: install kernel image and System.map ==="
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
echo "=== Step 5 done ==="

# Nettoyer le répertoire de build
rm -rf /sources/kernel-build
EOF

# Vérifier le code de retour de la dernière commande
if [ $? -ne 0 ]; then
    log_error "Kernel compilation failed"
    exit 1
fi

log_success "Kernel $KERNEL_TYPE compiled and installed to $LFS/boot/vmlinuz (architecture: $TARGET_ARCH)"