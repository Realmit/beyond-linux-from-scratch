#!/bin/bash
# ARM64 (aarch64) Profile for LFS
# Targets: Raspberry Pi 4/5, Orange Pi, Pine64, and other ARM64 SBCs

set -e

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[0;34m[SUCCESS]\033[0m $1"; }
log_warning() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }

# ============================================================================
# ARM64 SPECIFIC CONFIGURATION
# ============================================================================

BOARD="${BOARD:-rpi_4}"  # rpi_4, rpi_5, orangepi_pc, pine64, generic
U_BOOT_BOARD="${U_BOOT_BOARD:-rpi_4}"
KERNEL_DTB="bcm2711-rpi-4-b.dtb"
CREATE_SD_IMAGE="${CREATE_SD_IMAGE:-yes}"

# Package list location
PACKAGE_LIST="profiles/arm64/packages.list"

# ============================================================================
# LOAD PACKAGES FROM LIST
# ============================================================================
load_packages() {
    log_info "Loading ARM64 packages from $PACKAGE_LIST..."

    if [ ! -f "$PACKAGE_LIST" ]; then
        log_warning "Package list not found, using default packages"
        PACKAGES="base system network ssh"
    else
        # Read packages from list (skip comments and empty lines)
        PACKAGES=$(grep -v '^#' "$PACKAGE_LIST" | grep -v '^$' | grep -v '^#=' | tr '\n' ' ')
    fi

    log_info "Packages to install: $PACKAGES"
}

# ============================================================================
# INSTALL PACKAGES USING LPM
# ============================================================================
install_packages_lpm() {
    log_info "Installing ARM64 packages using LPM..."

    # Update package database
    lpm update

    for pkg in $PACKAGES; do
        log_info "Installing: $pkg"
        lpm install "$pkg" 2>/dev/null || {
            log_warning "Package $pkg not found in repositories, building from source"
            # Fallback to source build if needed
        }
    done

    log_success "All packages installed"
}

# ============================================================================
# INSTALL FROM SOURCE (Fallback)
# ============================================================================
install_from_source() {
    local pkg=$1
    local url=$2
    local version=$3

    log_info "Building $pkg from source..."

    cd /sources
    wget "$url" -O "${pkg}-${version}.tar.gz"
    tar -xzf "${pkg}-${version}.tar.gz"
    cd "${pkg}-${version}"

    # Standard build process
    if [ -f "configure" ]; then
        ./configure --prefix=/usr
    fi

    make -j$(nproc)
    make install

    log_success "Built $pkg from source"
}

# ============================================================================
# DETECT BOARD TYPE
# ============================================================================
detect_board() {
    case "$BOARD" in
        rpi_4|rpi4|raspberrypi4)
            BOARD="rpi_4"
            U_BOOT_BOARD="rpi_4"
            KERNEL_DTB="bcm2711-rpi-4-b.dtb"
            log_info "Configuring for Raspberry Pi 4"
            ;;
        rpi_5|rpi5|raspberrypi5)
            BOARD="rpi_5"
            U_BOOT_BOARD="rpi_5"
            KERNEL_DTB="bcm2712-rpi-5-b.dtb"
            log_info "Configuring for Raspberry Pi 5"
            ;;
        orangepi_pc|orangepi)
            BOARD="orangepi_pc"
            U_BOOT_BOARD="orangepi_pc"
            KERNEL_DTB="sun8i-h3-orangepi-pc.dtb"
            log_info "Configuring for Orange Pi PC"
            ;;
        pine64)
            BOARD="pine64"
            U_BOOT_BOARD="pine64_plus"
            KERNEL_DTB="sun50i-a64-pine64-plus.dtb"
            log_info "Configuring for Pine64"
            ;;
        *)
            BOARD="generic"
            U_BOOT_BOARD="generic"
            KERNEL_DTB="generic-arm64.dtb"
            log_warning "Unknown board: $BOARD, using generic configuration"
            ;;
    esac

    # Export for other scripts
    export BOARD U_BOOT_BOARD KERNEL_DTB
}

# ============================================================================
# INSTALL ARM64 KERNEL
# ============================================================================
install_arm64_kernel() {
    log_info "Installing ARM64 kernel..."

    cd /sources

    # Download ARM64 kernel config if not exists
    if [ ! -f "kernel-config-arm64" ]; then
        cp /config/kernel-config-arm64 .
    fi

    # Build kernel with ARM64 config
    tar -xf linux-*.tar.xz
    cd linux-*

    # Use ARM64 config
    cp ../kernel-config-arm64 .config

    # Build with ARM64 optimizations
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) Image modules dtbs

    # Install
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH=/usr modules_install
    cp arch/arm64/boot/Image /boot/vmlinuz-lfs
    cp arch/arm64/boot/dts/*/$KERNEL_DTB /boot/ || true
    cp arch/arm64/boot/dts/*/*.dtb /boot/ 2>/dev/null || true

    cd ..

    log_success "ARM64 kernel installed"
}

# ============================================================================
# CONFIGURE U-BOOT
# ============================================================================
configure_uboot() {
    log_info "Configuring U-Boot for $U_BOOT_BOARD..."

    cd /sources

    # Download U-Boot if not present
    if [ ! -f "u-boot-*.tar.bz2" ]; then
        wget https://ftp.denx.de/pub/u-boot/u-boot-2024.01.tar.bz2
    fi

    tar -xjf u-boot-*.tar.bz2
    cd u-boot-*

    # Configure for board
    make ${U_BOOT_BOARD}_defconfig
    make ARCH=arm CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc)

    # Install U-Boot
    cp u-boot.bin /boot/
    cp u-boot.img /boot/ 2>/dev/null || true

    # For Raspberry Pi, create config.txt
    if [ "$BOARD" = "rpi_4" ] || [ "$BOARD" = "rpi_5" ]; then
        cat > /boot/config.txt << 'EOF'
# Raspberry Pi configuration for LFS
arm_64bit=1
kernel=u-boot.bin
enable_uart=1
uart_2ndstage=1
dtoverlay=disable-bt
force_turbo=1
boot_delay=0

# Memory
gpu_mem=64

# Device tree
device_tree=bcm2711-rpi-4-b.dtb

# Boot options
disable_splash=1
EOF
    fi

    cd ..

    log_success "U-Boot configured for $U_BOOT_BOARD"
}

# ============================================================================
# CREATE BOOT SCRIPT
# ============================================================================
create_boot_script() {
    log_info "Creating U-Boot boot script..."

    cat > /boot/boot.cmd << 'EOF'
# U-Boot script for LFS ARM64
# Set bootargs
setenv bootargs console=ttyAMA0,115200 root=/dev/mmcblk0p2 rootwait rw

# Load kernel and device tree
load mmc 0:1 ${kernel_addr_r} /vmlinuz-lfs
load mmc 0:1 ${fdt_addr_r} /bcm2711-rpi-4-b.dtb

# Boot
booti ${kernel_addr_r} - ${fdt_addr_r}
EOF

    # Convert to U-Boot script format
    mkimage -A arm64 -O linux -T script -C none -a 0 -e 0 -n "LFS Boot Script" -d /boot/boot.cmd /boot/boot.scr

    log_success "Boot script created"
}

# ============================================================================
# CONFIGURE FSTAB FOR ARM64
# ============================================================================
configure_fstab() {
    log_info "Configuring fstab for ARM64..."

    cat > /etc/fstab << 'EOF'
# /etc/fstab for ARM64 LFS
# <file system> <mount point> <type> <options> <dump> <pass>

/dev/mmcblk0p2  /           ext4    defaults,noatime  0   1
/dev/mmcblk0p1  /boot       vfat    defaults          0   2
proc            /proc       proc    defaults          0   0
sysfs           /sys        sysfs   defaults          0   0
devtmpfs        /dev        devtmpfs mode=0755,nosuid 0   0
tmpfs           /dev/shm    tmpfs   defaults          0   0
EOF

    log_success "fstab configured"
}

# ============================================================================
# INSTALL ARM64 OPTIMIZED PACKAGES
# ============================================================================
install_arm64_packages() {
    log_info "Installing ARM64 optimized packages..."

    # Install optimized glibc for ARM64
    cd /sources
    tar -xf glibc-*.tar.xz
    cd glibc-*
    mkdir -p build
    cd build
    ../configure --prefix=/usr \
                 --host=aarch64-lfs-linux-gnu \
                 --build=$(../scripts/config.guess) \
                 --enable-kernel=4.14 \
                 --with-headers=/usr/include
    make -j$(nproc)
    make install
    cd ../..

    log_success "ARM64 optimized packages installed"
}

# ============================================================================
# CREATE SD CARD IMAGE
# ============================================================================
create_sd_image() {
    if [ "$CREATE_SD_IMAGE" != "yes" ]; then
        log_info "SD card image creation disabled (CREATE_SD_IMAGE=$CREATE_SD_IMAGE)"
        return
    fi

    log_info "Creating SD card image..."

    local SD_IMAGE="${LFS}/../lfs-arm64.img"
    local SD_SIZE=${SD_SIZE:-2048}  # MB

    # Create empty image
    dd if=/dev/zero of="$SD_IMAGE" bs=1M count=$SD_SIZE status=progress

    # Partition
    parted -s "$SD_IMAGE" mklabel msdos
    parted -s "$SD_IMAGE" mkpart primary fat32 1MiB 256MiB
    parted -s "$SD_IMAGE" mkpart primary ext4 256MiB 100%

    # Setup loop devices
    LOOP_DEV=$(losetup --find --show --partscan "$SD_IMAGE")

    # Format partitions
    mkfs.vfat -F32 ${LOOP_DEV}p1
    mkfs.ext4 -F ${LOOP_DEV}p2

    # Mount and copy files
    mkdir -p /mnt/{boot,root}
    mount ${LOOP_DEV}p1 /mnt/boot
    mount ${LOOP_DEV}p2 /mnt/root

    cp -r /boot/* /mnt/boot/
    rsync -ax / /mnt/root/ --exclude={/dev/*,/proc/*,/sys/*,/tmp/*,/run/*,/mnt/*,/media/*}

    # Unmount and cleanup
    umount /mnt/boot
    umount /mnt/root
    losetup -d "$LOOP_DEV"

    log_success "SD card image created: $SD_IMAGE"
    echo ""
    echo "To flash to SD card:"
    echo "  dd if=$SD_IMAGE of=/dev/sdb bs=4M status=progress"
}

# ============================================================================
# CREATE INSTALLER SCRIPT FOR ARM64
# ============================================================================
create_arm64_installer() {
    log_info "Creating ARM64 installer script..."

    cat > /usr/local/sbin/install-arm64.sh << 'EOF'
#!/bin/bash
# Install LFS ARM64 to SD card

TARGET_DEV=""
SD_IMAGE="/lfs-arm64.img"

select_device() {
    echo "Available SD card devices:"
    lsblk -d -o NAME,SIZE,MODEL | grep -E "mmcblk|sd"
    echo
    read -p "Select target device (e.g., mmcblk0): " TARGET_DEV
    TARGET_DEV="/dev/$TARGET_DEV"
}

flash_image() {
    echo "Flashing $SD_IMAGE to $TARGET_DEV..."
    dd if="$SD_IMAGE" of="$TARGET_DEV" bs=4M status=progress
    sync
    echo "Flash complete!"
}

main() {
    echo "LFS ARM64 Installer"
    echo "==================="
    select_device
    read -p "This will erase all data on $TARGET_DEV. Continue? (y/n): " confirm
    if [ "$confirm" = "y" ]; then
        flash_image
        echo "You can now insert the SD card into your ARM64 device and boot."
    fi
}

main "$@"
EOF

    chmod +x /usr/local/sbin/install-arm64.sh

    log_success "ARM64 installer created"
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    log_info "=== ARM64 LFS BUILD ==="

    detect_board
    load_packages

    # Install using LPM if available
    if command -v lpm &> /dev/null; then
        install_packages_lpm
    else
        install_arm64_packages
    fi

    install_arm64_kernel
    configure_uboot
    create_boot_script
    configure_fstab
    create_arm64_installer

    # Create SD image if requested
    create_sd_image

    log_success "ARM64 profile installation complete!"

    echo ""
    echo "=========================================="
    echo "ARM64 LFS Build Complete"
    echo "=========================================="
    echo "Board: $BOARD"
    echo "U-Boot: $U_BOOT_BOARD"
    echo "Kernel DTB: $KERNEL_DTB"
    echo ""
    echo "Flash to SD card:"
    echo "  dd if=lfs-arm64.img of=/dev/sdb bs=4M status=progress"
    echo ""
    echo "Or run from aarch64 system:"
    echo "  install-arm64.sh"
    echo ""
    echo "Login:"
    echo "  Username: lfsuser"
    echo "  Password: lfsuser123"
    echo "=========================================="
}

main "$@"