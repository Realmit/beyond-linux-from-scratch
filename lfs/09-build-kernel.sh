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

# Détection de Docker
IN_DOCKER=false
if [ -f /.dockerenv ] || [ -f /run/.containerenv ] || grep -q docker /proc/1/cgroup 2>/dev/null; then
    IN_DOCKER=true
    log_info "Running in Docker container"
fi

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
# Extraire le noyau : mode Docker vs natif
# ============================================================================
KERNEL_BUILD_DIR="$LFS/sources/kernel-build"

if [ "$IN_DOCKER" = true ]; then
    # Mode Docker : extraire directement dans kernel-build avec --strip-components=1
    rm -rf "$KERNEL_BUILD_DIR"
    mkdir -p "$KERNEL_BUILD_DIR"
    log_info "Docker mode: extracting kernel source to $KERNEL_BUILD_DIR"
    # --strip-components=1 enlève le répertoire racine (ex: linux-6.12.10)
    if ! tar -xf "$LFS/sources/$KERNEL_ARCHIVE" -C "$KERNEL_BUILD_DIR" --strip-components=1 --no-same-owner 2>&1 | tee "$LFS/tmp/tar-extract.log"; then
        log_error "Failed to extract kernel archive"
        log_info "Tar extraction log:"
        cat "$LFS/tmp/tar-extract.log" || true
        exit 1
    fi
    log_info "Kernel extracted in Docker mode"

else
    # Mode natif : extraire sur l'hôte et copier dans le chroot
    WORKDIR=$(mktemp -d)
    log_info "Extracting kernel source on host to $WORKDIR"
    tar -xf "$LFS/sources/$KERNEL_ARCHIVE" -C "$WORKDIR"
    KERNEL_DIR=$(tar -tf "$LFS/sources/$KERNEL_ARCHIVE" | head -1 | cut -d/ -f1)
    EXTRACTED_KERNEL="$WORKDIR/$KERNEL_DIR"
    log_info "Kernel extracted to $EXTRACTED_KERNEL"

    rm -rf "$KERNEL_BUILD_DIR"
    mkdir -p "$KERNEL_BUILD_DIR"
    cp -rv "$EXTRACTED_KERNEL"/* "$KERNEL_BUILD_DIR/"
    chown -R lfs:lfs "$KERNEL_BUILD_DIR" 2>/dev/null || true
    rm -rf "$WORKDIR"
fi

# ============================================================================
# BIND MOUNTS COMPLETS (y compris /usr)
# ============================================================================
mkdir -p "$LFS/bin" "$LFS/usr" "$LFS/lib" "$LFS/lib64"

# Monter TOUT /usr de l'hôte dans le chroot (donne accès à /usr/bin, /usr/lib, etc.)
mountpoint -q "$LFS/usr"  || mount --bind /usr "$LFS/usr"
mountpoint -q "$LFS/bin"  || mount --bind /bin "$LFS/bin"
mountpoint -q "$LFS/lib"  || mount --bind /lib "$LFS/lib"
mountpoint -q "$LFS/lib64" || mount --bind /lib64 "$LFS/lib64"

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
    umount "$LFS/usr" 2>/dev/null || true
    umount "$LFS/lib" 2>/dev/null || true
    umount "$LFS/lib64" 2>/dev/null || true
}
trap cleanup EXIT

# ============================================================================
# DIAGNOSTIC : Vérification du chroot
# ============================================================================
log_info "=== DIAGNOSTIC : Vérification du chroot ==="
if chroot "$LFS" /bin/bash -c "exit 0" 2>/dev/null; then
    log_success "/bin/bash works in chroot"
else
    log_error "/bin/bash does not work in chroot"
    exit 1
fi

if chroot "$LFS" /usr/bin/head -n1 /etc/hosts >/dev/null 2>&1; then
    log_success "head works in chroot"
else
    log_error "head not found in chroot"
    exit 1
fi

if chroot "$LFS" /usr/bin/env >/dev/null 2>&1; then
    log_success "env works in chroot"
else
    log_error "env not found in chroot"
    exit 1
fi

if chroot "$LFS" /usr/bin/gcc --version >/dev/null 2>&1; then
    log_success "gcc found in chroot"
else
    log_error "gcc not found in chroot"
    exit 1
fi

if chroot "$LFS" /usr/bin/make --version >/dev/null 2>&1; then
    log_success "make found in chroot"
else
    log_error "make not found in chroot"
    exit 1
fi

# ============================================================================
# Compilation dans le chroot avec PATH complet
# ============================================================================
log_info "=== Début de la compilation du noyau ==="
log_info "Architecture: $MAKE_ARCH"
log_info "Répertoire de build: $KERNEL_BUILD_DIR"

set +e

chroot "$LFS" /bin/bash << EOF_LOGGED
set -e
cd /sources/kernel-build

# Vider le log précédent
> /tmp/kernel-build.log

# Définir un PATH complet pour avoir accès à toutes les commandes
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export CC="gcc"
export HOSTCC="gcc"
export CXX="g++"
export HOSTCXX="g++"

# Vérifier les commandes essentielles
echo "[LOG] Vérification des commandes essentielles" >> /tmp/kernel-build.log
which head >> /tmp/kernel-build.log 2>&1 || echo "head not found" >> /tmp/kernel-build.log
which env >> /tmp/kernel-build.log 2>&1 || echo "env not found" >> /tmp/kernel-build.log
which uname >> /tmp/kernel-build.log 2>&1 || echo "uname not found" >> /tmp/kernel-build.log
which tail >> /tmp/kernel-build.log 2>&1 || echo "tail not found" >> /tmp/kernel-build.log

echo "[LOG] Début de make mrproper" >> /tmp/kernel-build.log
make ARCH="$MAKE_ARCH" mrproper >> /tmp/kernel-build.log 2>&1
echo "[LOG] make mrproper terminé avec code \$?" >> /tmp/kernel-build.log

echo "[LOG] Début de make defconfig" >> /tmp/kernel-build.log
make ARCH="$MAKE_ARCH" defconfig >> /tmp/kernel-build.log 2>&1
echo "[LOG] make defconfig terminé avec code \$?" >> /tmp/kernel-build.log

echo "[LOG] Début de make -j\$(nproc)" >> /tmp/kernel-build.log
make ARCH="$MAKE_ARCH" -j\$(nproc) >> /tmp/kernel-build.log 2>&1
echo "[LOG] make terminé avec code \$?" >> /tmp/kernel-build.log

echo "[LOG] Début de make modules_install" >> /tmp/kernel-build.log
make ARCH="$MAKE_ARCH" modules_install >> /tmp/kernel-build.log 2>&1
echo "[LOG] make modules_install terminé avec code \$?" >> /tmp/kernel-build.log

# Copier l'image du noyau et System.map
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
    echo "ERROR: No kernel image found" >> /tmp/kernel-build.log
    exit 1
fi
cp System.map /boot/System.map

# Nettoyer le répertoire de build
rm -rf /sources/kernel-build

echo "[LOG] Compilation terminée avec succès" >> /tmp/kernel-build.log
EOF_LOGGED

CHROOT_EXIT=$?
set -e

if [ -f "$LFS/tmp/kernel-build.log" ]; then
    log_info "=== LOG DE COMPILATION COMPLET ==="
    cat "$LFS/tmp/kernel-build.log"
    cp "$LFS/tmp/kernel-build.log" /tmp/kernel-build.full.log
    rm -f "$LFS/tmp/kernel-build.log"
else
    log_error "Le fichier de log n'a pas été créé dans le chroot"
fi

if [ $CHROOT_EXIT -ne 0 ]; then
    log_error "La compilation a échoué avec le code $CHROOT_EXIT"
    exit $CHROOT_EXIT
fi

log_success "Kernel $KERNEL_TYPE compiled and installed to $LFS/boot/vmlinuz (architecture: $TARGET_ARCH)"