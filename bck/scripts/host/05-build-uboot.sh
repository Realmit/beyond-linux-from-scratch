#!/bin/bash
# Build U-Boot bootloader for ARM boards

source scripts/common/utils.sh

log_info "Building U-Boot bootloader"

# Configuration
U_BOOT_VERSION="2024.01"
U_BOOT_URL="https://ftp.denx.de/pub/u-boot/u-boot-${U_BOOT_VERSION}.tar.bz2"
U_BOOT_SOURCE="/sources/u-boot-${U_BOOT_VERSION}"

# Board configuration (default to Raspberry Pi 4)
BOARD="${BOARD:-rpi_4}"
BOARD_CONFIG="${BOARD}_defconfig"

cd /sources

# Download U-Boot if not exists
if [ ! -f "u-boot-${U_BOOT_VERSION}.tar.bz2" ]; then
    wget "$U_BOOT_URL"
fi

# Extract
tar -xjf "u-boot-${U_BOOT_VERSION}.tar.bz2"
cd "$U_BOOT_SOURCE"

# Configure for specific board
log_info "Configuring U-Boot for $BOARD"
make "$BOARD_CONFIG"

# Build
log_info "Building U-Boot"
make -j$(nproc)

# Install
mkdir -p "$LFS/boot"
cp u-boot.bin "$LFS/boot/"
if [ -f "u-boot.img" ]; then
    cp u-boot.img "$LFS/boot/"
fi

# Device tree blobs
if [ -d "arch/arm/dts" ]; then
    cp arch/arm/dts/*.dtb "$LFS/boot/" 2>/dev/null || true
fi

log_success "U-Boot built for $BOARD"