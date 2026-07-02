#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
    echo "[INFO] Relaunching with sudo..."
    exec sudo -E "$0" "$@"
fi

LFS=${LFS:-/mnt/lfs}
KERNEL_TYPE=${KERNEL_TYPE:-linux}

# ============================================================================
# DÉTECTION DE L'ARCHITECTURE CIBLE
# ============================================================================
# Si ARCH est définie dans l'environnement, on l'utilise
# Sinon, on déduit depuis LFS_TGT (ex: aarch64-lfs-linux-gnu → aarch64)
if [ -n "$ARCH" ]; then
    TARGET_ARCH="$ARCH"
elif [ -n "$LFS_TGT" ]; then
    TARGET_ARCH=$(echo "$LFS_TGT" | cut -d- -f1)
else
    # Fallback : architecture de l'hôte (pour compilation native)
    TARGET_ARCH=$(uname -m)
fi

# Normaliser les noms d'architecture pour make
case "$TARGET_ARCH" in
    x86_64|amd64)
        MAKE_ARCH="x86_64"
        ;;
    aarch64|arm64)
        MAKE_ARCH="arm64"
        ;;
    armv7l|armhf)
        MAKE_ARCH="arm"
        ;;
    riscv64)
        MAKE_ARCH="riscv"
        ;;
    *)
        MAKE_ARCH="$TARGET_ARCH"
        ;;
esac

log_info() { echo "[INFO] $*"; }
log_error() { echo "[ERROR] $*" >&2; }
log_success() { echo "[SUCCESS] $*"; }

log_info "Target architecture: $TARGET_ARCH (make ARCH=$MAKE_ARCH)"

# ============================================================================
# VÉRIFICATION DES OUTILS SUR L'HÔTE
# ============================================================================
for cmd in make gcc tar xz; do
    if ! command -v "$cmd" &> /dev/null; then
        log_error "Required command '$cmd' not found on host"
        exit 1
    fi
done
log_success "All required tools found on host"

# Si on cross-compile, vérifier le compilateur croisé
if [ "$TARGET_ARCH" != "$(uname -m)" ]; then
    CROSS_COMPILE="${TARGET_ARCH}-linux-gnu-"
    if ! command -v "${CROSS_COMPILE}gcc" &> /dev/null; then
        log_error "Cross-compiler not found: ${CROSS_COMPILE}gcc"
        log_info "Install with: apt install gcc-${TARGET_ARCH}-linux-gnu binutils-${TARGET_ARCH}-linux-gnu"
        exit 1
    fi
    export CROSS_COMPILE
    log_info "Cross-compilation enabled: CROSS_COMPILE=$CROSS_COMPILE"
else
    log_info "Native compilation (same as host)"
fi

# ============================================================================
# SOURCES
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

cd "$LFS/sources"
KERNEL_ARCHIVE=$(ls -1 "${KERNEL_TYPE}"-*.tar.xz 2>/dev/null | head -n1)
if [ -z "$KERNEL_ARCHIVE" ]; then
    log_error "No kernel source found for type: $KERNEL_TYPE"
    exit 1
fi
log_info "Using kernel source: $KERNEL_ARCHIVE"

# ============================================================================
# SKIP SI DÉJÀ INSTALLÉ
# ============================================================================
if [ -f "$LFS/boot/vmlinuz" ]; then
    log_info "Kernel already installed at $LFS/boot/vmlinuz – skipping"
    exit 0
fi

# ============================================================================
# COMPILATION SUR L'HÔTE (AVEC LA BONNE ARCHITECTURE)
# ============================================================================
WORKDIR=$(mktemp -d)
cd "$WORKDIR"

log_info "Extracting kernel source"
tar -xf "$LFS/sources/$KERNEL_ARCHIVE"
KERNEL_DIR=$(tar -tf "$LFS/sources/$KERNEL_ARCHIVE" | head -1 | cut -d/ -f1)
cd "$KERNEL_DIR"

log_info "Configuring kernel (defconfig) for architecture $MAKE_ARCH"
make ARCH="$MAKE_ARCH" defconfig

log_info "Building kernel with $(nproc) jobs"
make ARCH="$MAKE_ARCH" -j$(nproc)

# ============================================================================
# INSTALLATION DANS $LFS
# ============================================================================
log_info "Installing modules to $LFS"
make ARCH="$MAKE_ARCH" modules_install INSTALL_MOD_PATH="$LFS"

log_info "Copying kernel and System.map"
mkdir -p "$LFS/boot"
cp arch/$MAKE_ARCH/boot/bzImage "$LFS/boot/vmlinuz" 2>/dev/null || \
cp arch/$MAKE_ARCH/boot/Image "$LFS/boot/vmlinuz"    2>/dev/null || \
cp vmlinuz "$LFS/boot/vmlinuz"                       2>/dev/null || \
cp arch/$MAKE_ARCH/boot/zImage "$LFS/boot/vmlinuz"  2>/dev/null
cp System.map "$LFS/boot/System.map"

# ============================================================================
# NETTOYAGE
# ============================================================================
cd /
rm -rf "$WORKDIR"

log_success "Kernel $KERNEL_TYPE compiled and installed to $LFS/boot/vmlinuz (architecture: $TARGET_ARCH)"