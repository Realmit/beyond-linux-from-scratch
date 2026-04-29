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

# Create installer initramfs
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
    echo "LFS Linux Installer"
    echo "==================="
    echo "1) Install LFS to disk"
    echo "2) Run live system"
    echo "3) Partition disk"
    echo "4) Exit to shell"
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

# Create installer script
cat > $LFS/usr/sbin/lfs-installer << "EOF"
#!/bin/bash

# LFS Installer Script
TARGET_DISK=""
LFS_VERSION="1.0"

select_disk() {
    echo "Available disks:"
    lsblk -d -o NAME,SIZE,MODEL
    echo
    read -p "Select target disk (e.g., sda): " TARGET_DISK
    TARGET_DISK="/dev/$TARGET_DISK"
}

partition_disk() {
    echo "Partitioning $TARGET_DISK"

    # Wipe filesystem signatures
    wipefs -a $TARGET_DISK

    # Create partitions
    parted -s $TARGET_DISK mklabel gpt
    parted -s $TARGET_DISK mkpart primary fat32 1MiB 513MiB
    parted -s $TARGET_DISK mkpart primary linux-swap 513MiB 2561MiB
    parted -s $TARGET_DISK mkpart primary ext4 2561MiB 100%
    parted -s $TARGET_DISK set 1 esp on

    # Format partitions
    mkfs.vfat -F32 ${TARGET_DISK}1
    mkswap ${TARGET_DISK}2
    mkfs.ext4 -F ${TARGET_DISK}3
}

install_system() {
    echo "Installing LFS to ${TARGET_DISK}3"

    # Mount target partitions
    mount ${TARGET_DISK}3 /mnt
    mkdir -p /mnt/boot
    mount ${TARGET_DISK}1 /mnt/boot
    swapon ${TARGET_DISK}2

    # Copy system
    rsync -avx --exclude={/dev/*,/proc/*,/sys/*,/tmp/*,/run/*,/mnt/*,/media/*,/lost+found} / /mnt/

    # Setup bootloader
    chroot /mnt /bin/bash -c "grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=LFS"
    chroot /mnt /bin/bash -c "grub-mkconfig -o /boot/grub/grub.cfg"

    echo "Installation complete!"
    umount -R /mnt
}

# Main installer
echo "LFS Linux Installer v$LFS_VERSION"
select_disk
partition_disk
install_system
echo "Installation finished. Reboot to start LFS."
EOF

chmod +x $LFS/usr/sbin/lfs-installer

# Build initramfs for installer
cd $INSTALLER_DIR
find . | cpio -o -H newc | gzip > $INSTALLER_DIR/installer.img

# Create ISO with isolinux
isolinux_bin="/usr/lib/syslinux/isolinux.bin"
if [ ! -f "$isolinux_bin" ]; then
    isolinux_bin="/usr/share/syslinux/isolinux.bin"
fi

cat > $INSTALLER_DIR/isolinux/isolinux.cfg << "EOF"
DEFAULT install
LABEL install
  KERNEL /boot/vmlinuz
  APPEND initrd=/boot/initramfs.img root=/dev/ram0
LABEL live
  KERNEL /boot/vmlinuz
  APPEND initrd=/boot/initramfs.img root=/dev/ram0
EOF

# Create ISO
xorriso -as mkisofs -R -J -joliet-long \
    -b isolinux/isolinux.bin -c isolinux/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -eltorito-alt-boot -e boot/efi.img -no-emul-boot \
    -isohybrid-gpt-basdat \
    -V "LFS_LINUX" \
    -o "../$ISO_NAME" \
    "$INSTALLER_DIR"

log_info "Installer ISO created: $ISO_NAME"