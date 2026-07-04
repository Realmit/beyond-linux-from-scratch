#!/bin/bash
set -e

# Re‑launch with sudo if not root
if [ "$EUID" -ne 0 ]; then
    echo "[INFO] Relaunching with sudo..."
    exec sudo -E "$0" "$@"
fi

# ---------------------------------------------------------------------------
# Variables from builder.py
# ---------------------------------------------------------------------------
LFS=${LFS:-/mnt/lfs}
KERNEL_TYPE=${KERNEL_TYPE:-linux}
ARCH=${ARCH:-$(uname -m)}
LFS_TGT=${LFS_TGT:-${ARCH}-lfs-linux-gnu}
CROSS_COMPILE=${CROSS_COMPILE:-}

# Normalise ARCH for make
case "$ARCH" in
    x86_64|amd64)  MAKE_ARCH="x86_64" ;;
    aarch64|arm64) MAKE_ARCH="arm64"  ;;
    armv7l|armhf)  MAKE_ARCH="arm"    ;;
    riscv64)       MAKE_ARCH="riscv"  ;;
    *)             MAKE_ARCH="$ARCH"  ;;
esac

KERNEL_VERSION=""

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log_info()    { echo "[INFO] $*"; }
log_error()   { echo "[ERROR] $*" >&2; }
log_success() { echo "[SUCCESS] $*"; }

# ---------------------------------------------------------------------------
# Check required host tools
# ---------------------------------------------------------------------------
for cmd in make gcc ld ar tar xz; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "Required host tool '$cmd' not found"
        exit 1
    fi
done

# ---------------------------------------------------------------------------
# Locate the kernel source tarball
# ---------------------------------------------------------------------------
cd "$LFS/sources" || { log_error "Sources directory not found"; exit 1; }

KERNEL_TARBALL=$(ls -1 "${KERNEL_TYPE}"-*.tar.xz 2>/dev/null | head -n1)
if [ -z "$KERNEL_TARBALL" ]; then
    log_error "No kernel source found for type '$KERNEL_TYPE'"
    exit 1
fi

KERNEL_VERSION=$(echo "$KERNEL_TARBALL" | sed -E 's/^[^-]+-([0-9]+\.[0-9]+\.[0-9]+)\.tar\..*$/\1/')
log_info "Kernel source: $KERNEL_TARBALL (version $KERNEL_VERSION)"

# ---------------------------------------------------------------------------
# Extract and compile on the host (in a temporary directory, not in $LFS)
# ---------------------------------------------------------------------------
WORKDIR=$(mktemp -d)
cd "$WORKDIR"

log_info "Extracting kernel source on host (temporary directory)"
tar -xf "$LFS/sources/$KERNEL_TARBALL"
KERNEL_DIR=$(tar -tf "$LFS/sources/$KERNEL_TARBALL" | head -1 | cut -d/ -f1)
cd "$KERNEL_DIR"

# Override all inherited compiler/linker/archiver variables
MAKE_CMD="make ARCH=$MAKE_ARCH"
MAKE_CMD="$MAKE_CMD CC=gcc HOSTCC=gcc"
MAKE_CMD="$MAKE_CMD CXX=g++ HOSTCXX=g++"
MAKE_CMD="$MAKE_CMD LD=ld HOSTLD=ld"
MAKE_CMD="$MAKE_CMD AR=ar HOSTAR=ar"
MAKE_CMD="$MAKE_CMD RANLIB=ranlib HOSTRANLIB=ranlib"
MAKE_CMD="$MAKE_CMD NM=nm HOSTNM=nm"
MAKE_CMD="$MAKE_CMD STRIP=strip HOSTSTRIP=strip"
MAKE_CMD="$MAKE_CMD OBJCOPY=objcopy HOSTOBJCOPY=objcopy"
MAKE_CMD="$MAKE_CMD OBJDUMP=objdump HOSTOBJDUMP=objdump"
MAKE_CMD="$MAKE_CMD READELF=readelf HOSTREADELF=readelf"

log_info "Configuring kernel (defconfig) for architecture $MAKE_ARCH"
$MAKE_CMD defconfig

log_info "Compiling kernel (make -j$(nproc))"
$MAKE_CMD ${CROSS_COMPILE:+CROSS_COMPILE="$CROSS_COMPILE"} -j$(nproc)

# ---------------------------------------------------------------------------
# Install modules directly into $LFS
# ---------------------------------------------------------------------------
log_info "Installing kernel modules to $LFS"
$MAKE_CMD ${CROSS_COMPILE:+CROSS_COMPILE="$CROSS_COMPILE"} modules_install INSTALL_MOD_PATH="$LFS"

# ---------------------------------------------------------------------------
# Copy kernel image, System.map, and config to $LFS/boot
# ---------------------------------------------------------------------------
log_info "Copying kernel image and System.map to $LFS/boot"
mkdir -p "$LFS/boot"

# Determine the kernel image name
if [ -f "arch/$MAKE_ARCH/boot/bzImage" ]; then
    KERNEL_IMAGE="arch/$MAKE_ARCH/boot/bzImage"
elif [ -f "arch/$MAKE_ARCH/boot/Image" ]; then
    KERNEL_IMAGE="arch/$MAKE_ARCH/boot/Image"
elif [ -f "vmlinuz" ]; then
    KERNEL_IMAGE="vmlinuz"
elif [ -f "arch/$MAKE_ARCH/boot/zImage" ]; then
    KERNEL_IMAGE="arch/$MAKE_ARCH/boot/zImage"
else
    log_error "No kernel image found (tried bzImage, Image, vmlinuz, zImage)"
    exit 1
fi

cp -iv "$KERNEL_IMAGE" "$LFS/boot/vmlinuz-${KERNEL_VERSION}-lfs-13.0"
cp -iv System.map "$LFS/boot/System.map-${KERNEL_VERSION}"
cp -iv .config "$LFS/boot/config-${KERNEL_VERSION}"

# Symlink for convenience
ln -sf "vmlinuz-${KERNEL_VERSION}-lfs-13.0" "$LFS/boot/vmlinuz"

# ---------------------------------------------------------------------------
# Clean up
# ---------------------------------------------------------------------------
cd /
rm -rf "$WORKDIR"

log_success "Kernel ${KERNEL_VERSION} compiled and installed to $LFS/boot"
log_info "You can now update your bootloader (GRUB) to use the new kernel."