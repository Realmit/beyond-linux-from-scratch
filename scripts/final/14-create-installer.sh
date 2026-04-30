#!/bin/bash
# Create bootable installer ISO

source scripts/common/utils.sh

ISO_NAME=${ISO_NAME:-lfs-installer.iso}
INSTALLER_DIR="$LFS/installer"

log_info "Creating installer ISO: $ISO_NAME"

# Create installer directory structure
mkdir -pv $INSTALLER_DIR/{boot,isolinux,images,rootfs}

# Copy kernel and initramfs
cp -v $LFS/boot/vmlinuz-* $INSTALLER_DIR/boot/vmlinuz
cp -v $LFS/boot/initramfs-* $INSTALLER_DIR/boot/initramfs.img

# ============================================================================
# COPY CUSTOM SCRIPTS TO THE IMAGE
# ============================================================================
log_info "Copying custom scripts to image..."

# Copy all custom scripts to the target system
if [ -d "packages/custom-scripts" ]; then
    # Copy to the LFS image
    cp -rv packages/custom-scripts/* "$LFS/usr/local/sbin/" 2>/dev/null || true
    chmod +x "$LFS/usr/local/sbin/"*.sh 2>/dev/null || true

    # Also copy to installer directory for live environment
    cp -rv packages/custom-scripts/* "$INSTALLER_DIR/rootfs/usr/local/sbin/" 2>/dev/null || true
    mkdir -p "$INSTALLER_DIR/rootfs/usr/local/sbin"
    chmod +x "$INSTALLER_DIR/rootfs/usr/local/sbin/"*.sh 2>/dev/null || true

    log_info "Custom scripts copied successfully"
else
    log_warning "packages/custom-scripts directory not found"
fi

# Copy theme setup script if exists
if [ -f "packages/custom-scripts/theme-setup.sh" ]; then
    log_info "Theme setup script will run on first boot"
    # Ensure first-boot service will run theme-setup
    cat > "$LFS/usr/local/sbin/run-theme-setup.sh" << 'EOF'
#!/bin/bash
if [ -f /usr/local/sbin/theme-setup.sh ]; then
    /usr/local/sbin/theme-setup.sh
fi
EOF
    chmod +x "$LFS/usr/local/sbin/run-theme-setup.sh"
fi

# ============================================================================
# CREATE FIRST-BOOT SYSTEMD SERVICE (if systemd is used)
# ============================================================================
if [ -d "$LFS/usr/lib/systemd" ]; then
    log_info "Creating first-boot systemd service"

    cat > "$LFS/etc/systemd/system/first-boot.service" << 'EOF'
[Unit]
Description=First Boot Setup
After=network.target
Before=display-manager.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/first-boot.sh
StandardOutput=journal+console

[Install]
WantedBy=multi-user.target
EOF

    # Enable the service in the target system
    ln -sf /etc/systemd/system/first-boot.service "$LFS/etc/systemd/system/multi-user.target.wants/first-boot.service" 2>/dev/null || true
fi

# ============================================================================
# CREATE FIRST-BOOT SYSV INIT SCRIPT (if sysv init is used)
# ============================================================================
if [ -d "$LFS/etc/rc.d" ]; then
    log_info "Creating first-boot sysv init script"

    cat > "$LFS/etc/rc.d/init.d/first-boot" << 'EOF'
#!/bin/sh
### BEGIN INIT INFO
# Provides:          first-boot
# Required-Start:    $remote_fs $network
# Required-Stop:
# Default-Start:     2 3 4 5
# Default-Stop:
# Short-Description: First boot setup
### END INIT INFO

case "$1" in
    start)
        if [ ! -f /var/lib/.first-boot-done ]; then
            echo "Running first boot setup..."
            /usr/local/sbin/first-boot.sh
        fi
        ;;
esac
EOF
    chmod +x "$LFS/etc/rc.d/init.d/first-boot"

    # Create symlinks for runlevels
    for rl in 2 3 4 5; do
        ln -sf ../init.d/first-boot "$LFS/etc/rc.d/rc$rl.d/S99first-boot" 2>/dev/null || true
    done
fi

# ============================================================================
# CREATE INSTALLER INITRAMFS
# ============================================================================
cat > $INSTALLER_DIR/init << "EOF"
#!/bin/busybox sh

# Mount proc and sys
mount -t proc none /proc
mount -t sysfs none /sys

# Detect installation media
detect_media() {
    for dev in /dev/sd* /dev/hd* /dev/nvme*; do
        if [ -b "$dev" ]; then
            mount "$dev" /mnt 2>/dev/null && break
        fi
    done
}

# Launch installer
launch_installer() {
    clear
    echo "========================================"
    echo "     LFS Linux Installer"
    echo "========================================"
    echo "1) Install LFS to disk"
    echo "2) Run live system"
    echo "3) Partition disk"
    echo "4) Exit to shell"
    echo "========================================"
    echo
    read -p "Choose option: " choice

    case $choice in
        1) /usr/sbin/lfs-installer ;;
        2) startx ;;
        3) cfdisk ;;
        4) /bin/sh ;;
        *) launch_installer ;;
    esac
}

# Main
detect_media
launch_installer
EOF

chmod +x $INSTALLER_DIR/init

# ============================================================================
# CREATE MAIN INSTALLER SCRIPT
# ============================================================================
cat > $LFS/usr/sbin/lfs-installer << "EOF"
#!/bin/bash

# LFS Installer Script
# Version: 3.0

TARGET_DISK=""
LFS_VERSION="3.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

select_disk() {
    echo "========================================"
    echo "Available disks:"
    echo "========================================"
    lsblk -d -o NAME,SIZE,MODEL
    echo
    read -p "Select target disk (e.g., sda): " TARGET_DISK
    TARGET_DISK="/dev/$TARGET_DISK"

    # Confirm
    read -p "WARNING: All data on $TARGET_DISK will be lost. Continue? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Installation aborted."
        exit 1
    fi
}

partition_disk() {
    log_info "Partitioning $TARGET_DISK"

    # Wipe filesystem signatures
    wipefs -a $TARGET_DISK 2>/dev/null || true

    # Create partitions
    parted -s $TARGET_DISK mklabel gpt
    parted -s $TARGET_DISK mkpart primary fat32 1MiB 513MiB
    parted -s $TARGET_DISK mkpart primary linux-swap 513MiB 2561MiB
    parted -s $TARGET_DISK mkpart primary ext4 2561MiB 100%
    parted -s $TARGET_DISK set 1 esp on

    # Format partitions
    log_info "Formatting partitions..."
    mkfs.vfat -F32 ${TARGET_DISK}1
    mkswap ${TARGET_DISK}2
    mkfs.ext4 -F ${TARGET_DISK}3
}

install_system() {
    log_info "Installing LFS to ${TARGET_DISK}3"

    # Mount target partitions
    mount ${TARGET_DISK}3 /mnt
    mkdir -p /mnt/boot
    mount ${TARGET_DISK}1 /mnt/boot
    swapon ${TARGET_DISK}2

    # Copy system
    log_info "Copying system files (this may take a while)..."
    rsync -avx --progress --exclude={/dev/*,/proc/*,/sys/*,/tmp/*,/run/*,/mnt/*,/media/*,/lost+found} / /mnt/

    # Setup bootloader
    log_info "Setting up bootloader..."
    if [ -d /sys/firmware/efi ]; then
        chroot /mnt /bin/bash -c "grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=LFS --recheck"
    else
        chroot /mnt /bin/bash -c "grub-install --target=i386-pc $TARGET_DISK"
    fi
    chroot /mnt /bin/bash -c "grub-mkconfig -o /boot/grub/grub.cfg"

    # Create first-boot flag (will be removed after first boot)
    touch /mnt/var/lib/.first-boot-pending

    log_info "Installation complete!"

    # Unmount
    umount -R /mnt
    swapoff ${TARGET_DISK}2
}

# Pre-installation checks
pre_install_checks() {
    # Check internet connection
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log_error "No internet connection. Please connect to network first."
        exit 1
    fi

    # Check disk space
    available=$(df / | awk 'NR==2 {print $4}')
    if [ "$available" -lt 4194304 ]; then  # 4GB
        log_error "Insufficient disk space. Need at least 4GB free."
        exit 1
    fi
}

# Main installer
main() {
    echo "========================================"
    echo "  LFS Linux Installer v$LFS_VERSION"
    echo "========================================"

    pre_install_checks
    select_disk
    partition_disk
    install_system

    echo ""
    echo "========================================"
    log_info "Installation finished successfully!"
    echo "========================================"
    echo ""
    echo "You can now reboot into your new LFS system."
    echo "After reboot, login with your credentials."
    echo ""
    read -p "Press Enter to reboot, or Ctrl+C to exit..."
    reboot
}

main "$@"
EOF

chmod +x $LFS/usr/sbin/lfs-installer

# ============================================================================
# BUILD INITRAMFS FOR INSTALLER
# ============================================================================
log_info "Building installer initramfs..."
cd $INSTALLER_DIR
find . | cpio -o -H newc | gzip > $INSTALLER_DIR/installer.img

# ============================================================================
# CREATE ISO WITH ISOLINUX
# ============================================================================
log_info "Creating ISO image..."

# Find isolinux binary
isolinux_bin="/usr/lib/syslinux/isolinux.bin"
if [ ! -f "$isolinux_bin" ]; then
    isolinux_bin="/usr/share/syslinux/isolinux.bin"
fi
if [ ! -f "$isolinux_bin" ]; then
    isolinux_bin="/usr/lib/ISOLINUX/isolinux.bin"
fi

# Create isolinux configuration
cat > $INSTALLER_DIR/isolinux/isolinux.cfg << "EOF"
DEFAULT lfs
TIMEOUT 50
PROMPT 1

UI vesamenu.c32
MENU TITLE LFS Linux Installer

LABEL lfs
    MENU LABEL ^Install LFS Linux
    KERNEL /boot/vmlinuz
    APPEND initrd=/boot/initramfs.img root=/dev/ram0 quiet

LABEL lfs-live
    MENU LABEL ^Run LFS Live
    KERNEL /boot/vmlinuz
    APPEND initrd=/boot/initramfs.img root=/dev/ram0 quiet

LABEL memtest
    MENU LABEL ^Memory Test
    KERNEL /boot/memtest86.bin

LABEL rescue
    MENU LABEL ^Rescue Mode
    KERNEL /boot/vmlinuz
    APPEND initrd=/boot/initramfs.img root=/dev/ram0 single

LABEL reboot
    MENU LABEL ^Reboot
    COM32 reboot.c32

LABEL harddisk
    MENU LABEL ^Boot from Hard Disk
    LOCALBOOT 0x80
EOF

# Create EFI boot image
log_info "Creating EFI boot image..."
dd if=/dev/zero of=$INSTALLER_DIR/boot/efi.img bs=1M count=20 2>/dev/null
mkfs.vfat $INSTALLER_DIR/boot/efi.img
mkdir -p $INSTALLER_DIR/efi/boot
mount -o loop $INSTALLER_DIR/boot/efi.img $INSTALLER_DIR/efi
cp -v $INSTALLER_DIR/boot/vmlinuz $INSTALLER_DIR/efi/boot/vmlinuz.efi
cp -v $INSTALLER_DIR/boot/initramfs.img $INSTALLER_DIR/efi/boot/initramfs.img
umount $INSTALLER_DIR/efi

# Create the final ISO
xorriso -as mkisofs -R -J -joliet-long \
    -b isolinux/isolinux.bin -c isolinux/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -eltorito-alt-boot -e boot/efi.img -no-emul-boot \
    -isohybrid-gpt-basdat \
    -V "LFS_LINUX" \
    -o "../$ISO_NAME" \
    "$INSTALLER_DIR"

# ============================================================================
# VERIFY ISO CREATION
# ============================================================================
if [ -f "../$ISO_NAME" ]; then
    ISO_SIZE=$(du -h "../$ISO_NAME" | cut -f1)
    log_success "Installer ISO created successfully!"
    log_info "ISO location: $(pwd)/../$ISO_NAME"
    log_info "ISO size: $ISO_SIZE"

    # Calculate checksum
    SHA256SUM=$(sha256sum "../$ISO_NAME" | cut -d' ' -f1)
    echo "$SHA256SUM  $ISO_NAME" > "../$ISO_NAME.sha256"
    log_info "SHA256 checksum saved to: $ISO_NAME.sha256"
else
    log_error "Failed to create ISO image"
    exit 1
fi

log_info "Installer creation complete!"