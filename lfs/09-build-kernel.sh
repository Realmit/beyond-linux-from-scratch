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
# 1. S'assurer que les sources du noyau sont disponibles
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
# 2. Si le noyau est déjà installé, on saute
# ============================================================================
if [ -f "$LFS/boot/vmlinuz" ]; then
    log_info "Kernel already installed at $LFS/boot/vmlinuz – skipping"
    exit 0
fi

# ============================================================================
# 3. Compilation sur l'hôte
# ============================================================================
WORKDIR=$(mktemp -d)
cd "$WORKDIR"

log_info "Extracting kernel source"
tar -xf "$LFS/sources/$KERNEL_ARCHIVE"
KERNEL_DIR=$(tar -tf "$LFS/sources/$KERNEL_ARCHIVE" | head -1 | cut -d/ -f1)
cd "$KERNEL_DIR"

log_info "Configuring kernel (defconfig)"
make defconfig

log_info "Building kernel with $(nproc) jobs"
make -j$(nproc)

# ============================================================================
# 4. Installation dans $LFS
# ============================================================================
log_info "Installing modules to $LFS"
make modules_install INSTALL_MOD_PATH="$LFS"

log_info "Copying kernel and System.map"
mkdir -p "$LFS/boot"
cp arch/x86/boot/bzImage "$LFS/boot/vmlinuz"
cp System.map "$LFS/boot/System.map"

# ============================================================================
# 5. Nettoyage
# ============================================================================
cd /
rm -rf "$WORKDIR"

log_success "Kernel $KERNEL_TYPE compiled and installed to $LFS/boot/vmlinuz"