#!/bin/bash
# Create bootable installer ISO with Live System support

source scripts/common/utils.sh

ISO_NAME=${ISO_NAME:-lfs-installer.iso}
INSTALLER_DIR="$LFS/installer"
LIVE_DIR="$LFS/live"

log_info "Creating installer ISO with Live System: $ISO_NAME"

# Create installer directory structure
mkdir -pv $INSTALLER_DIR/{boot,isolinux,images,rootfs}
mkdir -pv $LIVE_DIR/{rootfs,overlay,persistence}

# ============================================================================
# COPY CUSTOM SCRIPTS TO THE IMAGE
# ============================================================================
log_info "Copying custom scripts to image..."

if [ -d "packages/custom-scripts" ]; then
    cp -rv packages/custom-scripts/* "$LFS/usr/local/sbin/" 2>/dev/null || true
    chmod +x "$LFS/usr/local/sbin/"*.sh 2>/dev/null || true

    mkdir -p "$INSTALLER_DIR/rootfs/usr/local/sbin"
    cp -rv packages/custom-scripts/* "$INSTALLER_DIR/rootfs/usr/local/sbin/" 2>/dev/null || true
    chmod +x "$INSTALLER_DIR/rootfs/usr/local/sbin/"*.sh 2>/dev/null || true

    log_info "Custom scripts copied successfully"
fi

# ============================================================================
# CREATE LIVE SYSTEM SQUASHFS
# ============================================================================
log_info "Creating compressed live filesystem (squashfs)..."

# Install squashfs-tools if not present
if ! command -v mksquashfs &> /dev/null; then
    log_info "Installing squashfs-tools..."
    apt-get install -y squashfs-tools 2>/dev/null || yum install -y squashfs-tools 2>/dev/null || true
fi

# Create squashfs of root filesystem
mksquashfs $LFS $LIVE_DIR/rootfs/lfs.squashfs \
    -comp xz \
    -b 1M \
    -noappend \
    -progress \
    -wildcards \
    -e "proc/*" "sys/*" "dev/*" "tmp/*" "run/*" "mnt/*" "media/*" "lost+found/*" "$LIVE_DIR/*"

log_success "Live squashfs created"

# ============================================================================
# CREATE LIVE INITRAMFS
# ============================================================================
log_info "Creating live initramfs..."

cat > $LIVE_DIR/init << 'LIVEINIT'
#!/bin/busybox sh

# Live system init script
# Detects media, mounts squashfs, sets up overlay/persistence

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}[LIVE]${NC} Booting LFS Live System..."

# Mount basic filesystems
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev
mount -t tmpfs tmpfs /run

# Create necessary directories
mkdir -p /run/rootfs /run/overlay/{upper,work} /mnt/live /mnt/persistence /mnt/root

# Detect live media
detect_live_media() {
    for dev in /dev/sr0 /dev/sd* /dev/nvme* /dev/mmcblk*; do
        if [ -b "$dev" ]; then
            # Try to mount
            if mount -t iso9660 -o ro "$dev" /mnt/live 2>/dev/null; then
                if [ -f /mnt/live/live/rootfs/lfs.squashfs ]; then
                    LIVE_MOUNT="/mnt/live"
                    echo -e "${GREEN}[LIVE]${NC} Found live media on $dev"
                    return 0
                fi
                umount /mnt/live
            fi

            # Also check for vfat/ext4 (USB with persistence)
            if mount -t vfat -o rw "$dev" /mnt/live 2>/dev/null; then
                if [ -f /mnt/live/live/rootfs/lfs.squashfs ]; then
                    LIVE_MOUNT="/mnt/live"
                    echo -e "${GREEN}[LIVE]${NC} Found live USB on $dev"
                    return 0
                fi
                umount /mnt/live
            fi
        fi
    done
    return 1
}

# Mount squashfs
mount_squashfs() {
    echo -e "${GREEN}[LIVE]${NC} Mounting squashfs..."
    mount -t squashfs "$LIVE_MOUNT/live/rootfs/lfs.squashfs" /run/rootfs

    # Setup overlay for writable root
    echo -e "${GREEN}[LIVE]${NC} Setting up overlay filesystem..."
    mount -t overlay overlay \
        -o lowerdir=/run/rootfs,upperdir=/run/overlay/upper,workdir=/run/overlay/work \
        /mnt/root
}

# Check for persistence partition
check_persistence() {
    PERSISTENCE_LABEL="LFS-PERSIST"

    for dev in /dev/sd* /dev/nvme* /dev/mmcblk*; do
        if [ -b "${dev}1" ]; then
            LABEL=$(blkid -s LABEL -o value "${dev}1" 2>/dev/null)
            if [ "$LABEL" = "$PERSISTENCE_LABEL" ]; then
                echo -e "${GREEN}[LIVE]${NC} Found persistence partition on ${dev}1"
                echo "${dev}1"
                return 0
            fi
        fi
    done
    return 1
}

# Setup persistence overlay
setup_persistence() {
    local persist_dev=$1

    mount "$persist_dev" /mnt/persistence
    mkdir -p /mnt/persistence/{upper,work}

    # Remount overlay with persistence
    umount /mnt/root 2>/dev/null || true

    mount -t overlay overlay \
        -o lowerdir=/run/rootfs,upperdir=/mnt/persistence/upper,workdir=/mnt/persistence/work \
        /mnt/root

    echo -e "${GREEN}[LIVE]${NC} Persistence enabled - your changes will be saved!"
    touch /run/.persistence-enabled
}

# Main
main() {
    if ! detect_live_media; then
        echo -e "${YELLOW}[LIVE]${NC} Could not find live media"
        exec /bin/sh
    fi

    mount_squashfs

    # Check for persistence (if "persistence" in cmdline)
    if grep -q "persistence" /proc/cmdline; then
        PERSIST_DEV=$(check_persistence)
        if [ -n "$PERSIST_DEV" ]; then
            setup_persistence "$PERSIST_DEV"
        else
            echo -e "${YELLOW}[LIVE]${NC} No persistence partition found. Creating temporary overlay."
        fi
    fi

    # Mark as live system
    touch /run/.live-system

    # Cleanup and switch root
    umount /proc 2>/dev/null
    umount /sys 2>/dev/null

    # Run desktop if requested
    if grep -q "desktop" /proc/cmdline; then
        echo -e "${GREEN}[LIVE]${NC} Starting desktop environment..."
    fi

    exec switch_root /mnt/root /sbin/init
}

main "$@"
LIVEINIT

chmod +x $LIVE_DIR/init

# Create live initramfs
cd $LIVE_DIR
find . -name "init" | cpio -o -H newc | gzip > $INSTALLER_DIR/boot/live-initramfs.img
cd -

log_success "Live initramfs created"

# ============================================================================
# CREATE PERSISTENCE TOOL
# ============================================================================
log_info "Creating persistence setup tool..."

cat > $LFS/usr/local/sbin/create-persistence.sh << 'PERSISTTOOL'
#!/bin/bash
# Create persistence partition for live USB

PERSISTENCE_SIZE=${1:-2048}  # Size in MB

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

select_device() {
    echo "========================================"
    echo "Available USB devices:"
    echo "========================================"
    lsblk -d -o NAME,SIZE,MODEL | grep -E "sd|mmcblk"
    echo
    read -p "Select USB device (e.g., sdb): " USB_DEV
    USB_DEV="/dev/$USB_DEV"

    if [ ! -b "$USB_DEV" ]; then
        log_error "Device $USB_DEV not found"
        exit 1
    fi
}

create_persistence() {
    log_info "Creating persistence partition of ${PERSISTENCE_SIZE}MB on $USB_DEV"

    # Unmount any existing partitions
    umount ${USB_DEV}* 2>/dev/null || true

    # Create partition (preserve first partition for live system)
    parted -s $USB_DEV mkpart primary ext4 ${PERSISTENCE_SIZE}MiB 100%
    partprobe $USB_DEV

    # Sleep for device to settle
    sleep 2

    # Format with label
    mkfs.ext4 -F -L LFS-PERSIST ${USB_DEV}2

    # Create directories
    mkdir -p /mnt/persist
    mount ${USB_DEV}2 /mnt/persist
    mkdir -p /mnt/persist/{upper,work}
    umount /mnt/persist

    log_info "Persistence partition created successfully!"
    echo "  Device: ${USB_DEV}2"
    echo "  Label: LFS-PERSIST"
    echo "  Size: ${PERSISTENCE_SIZE}MB"
}

main() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run as root"
        exit 1
    fi

    select_device
    create_persistence
}

main "$@"
PERSISTTOOL

chmod +x $LFS/usr/local/sbin/create-persistence.sh

# ============================================================================
# CREATE FIRST-BOOT SYSTEMD SERVICE
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

    ln -sf /etc/systemd/system/first-boot.service "$LFS/etc/systemd/system/multi-user.target.wants/first-boot.service" 2>/dev/null || true
fi

# ============================================================================
# CREATE FIRST-BOOT SYSV INIT SCRIPT
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

    for rl in 2 3 4 5; do
        ln -sf ../init.d/first-boot "$LFS/etc/rc.d/rc$rl.d/S99first-boot" 2>/dev/null || true
    done
fi

# ============================================================================
# COPY KERNEL AND INITRAMFS
# ============================================================================
cp -v $LFS/boot/vmlinuz-* $INSTALLER_DIR/boot/vmlinuz
cp -v $LFS/boot/initramfs-* $INSTALLER_DIR/boot/initramfs.img

# ============================================================================
# CREATE INSTALLER INITRAMFS
# ============================================================================
cat > $INSTALLER_DIR/init << "EOF"
#!/bin/busybox sh

mount -t proc none /proc
mount -t sysfs none /sys

detect_media() {
    for dev in /dev/sd* /dev/hd* /dev/nvme*; do
        if [ -b "$dev" ]; then
            mount "$dev" /mnt 2>/dev/null && break
        fi
    done
}

launch_installer() {
    clear
    echo "========================================"
    echo "     LFS Linux Live & Installer"
    echo "========================================"
    echo "1) Try LFS Live (boot in RAM)"
    echo "2) Try LFS Live with Persistence"
    echo "3) Install LFS to disk"
    echo "4) Partition disk"
    echo "5) Exit to shell"
    echo "========================================"
    echo
    read -p "Choose option: " choice

    case $choice in
        1) /bin/kexec -l /boot/vmlinuz --initrd=/boot/live-initramfs.img --append="quiet splash desktop" && /bin/kexec -e ;;
        2) /bin/kexec -l /boot/vmlinuz --initrd=/boot/live-initramfs.img --append="quiet splash desktop persistence" && /bin/kexec -e ;;
        3) /usr/sbin/lfs-installer ;;
        4) cfdisk ;;
        5) /bin/sh ;;
        *) launch_installer ;;
    esac
}

detect_media
launch_installer
EOF

chmod +x $INSTALLER_DIR/init

# ============================================================================
# CREATE MAIN INSTALLER SCRIPT
# ============================================================================
cat > $LFS/usr/sbin/lfs-installer << 'INSTALLERSCRIPT'
#!/bin/bash

TARGET_DISK=""
LFS_VERSION="3.0"

RED='\033[0;31m'
GREEN='\033[0;32m'
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

    read -p "WARNING: All data on $TARGET_DISK will be lost. Continue? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        exit 1
    fi
}

partition_disk() {
    log_info "Partitioning $TARGET_DISK"
    wipefs -a $TARGET_DISK 2>/dev/null || true
    parted -s $TARGET_DISK mklabel gpt
    parted -s $TARGET_DISK mkpart primary fat32 1MiB 513MiB
    parted -s $TARGET_DISK mkpart primary linux-swap 513MiB 2561MiB
    parted -s $TARGET_DISK mkpart primary ext4 2561MiB 100%
    parted -s $TARGET_DISK set 1 esp on

    log_info "Formatting partitions..."
    mkfs.vfat -F32 ${TARGET_DISK}1
    mkswap ${TARGET_DISK}2
    mkfs.ext4 -F ${TARGET_DISK}3
}

install_system() {
    log_info "Installing LFS to ${TARGET_DISK}3"

    mount ${TARGET_DISK}3 /mnt
    mkdir -p /mnt/boot
    mount ${TARGET_DISK}1 /mnt/boot
    swapon ${TARGET_DISK}2

    log_info "Copying system files..."
    rsync -avx --exclude={/dev/*,/proc/*,/sys/*,/tmp/*,/run/*,/mnt/*,/media/*,/lost+found} / /mnt/

    log_info "Setting up bootloader..."
    if [ -d /sys/firmware/efi ]; then
        chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=LFS --recheck
    else
        chroot /mnt grub-install --target=i386-pc $TARGET_DISK
    fi
    chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

    touch /mnt/var/lib/.first-boot-pending

    log_info "Installation complete!"
    umount -R /mnt
    swapoff ${TARGET_DISK}2
}

pre_install_checks() {
    available=$(df / | awk 'NR==2 {print $4}')
    if [ "$available" -lt 4194304 ]; then
        log_error "Insufficient disk space. Need at least 4GB free."
        exit 1
    fi
}

main() {
    echo "========================================"
    echo "  LFS Linux Installer v$LFS_VERSION"
    echo "========================================"
    pre_install_checks
    select_disk
    partition_disk
    install_system

    echo ""
    log_info "Installation finished successfully!"
    echo ""
    read -p "Press Enter to reboot..."
    reboot
}

main "$@"
INSTALLERSCRIPT

chmod +x $LFS/usr/sbin/lfs-installer

# ============================================================================
# BUILD INITRAMFS
# ============================================================================
log_info "Building initramfs images..."

cd $INSTALLER_DIR
find . -name "init" -type f | cpio -o -H newc | gzip > $INSTALLER_DIR/installer.img
cd -

# ============================================================================
# CREATE BOOT MENU (ISOLINUX)
# ============================================================================
log_info "Creating boot menu..."

isolinux_bin="/usr/lib/syslinux/isolinux.bin"
[ ! -f "$isolinux_bin" ] && isolinux_bin="/usr/share/syslinux/isolinux.bin"
[ ! -f "$isolinux_bin" ] && isolinux_bin="/usr/lib/ISOLINUX/isolinux.bin"

cat > $INSTALLER_DIR/isolinux/isolinux.cfg << 'BOOTMENU'
DEFAULT lfs-live
TIMEOUT 100
PROMPT 1

UI vesamenu.c32
MENU TITLE LFS Linux - Live & Install
MENU BACKGROUND /boot/splash.png 2>/dev/null || true

LABEL lfs-live
    MENU LABEL ^Try LFS Linux (Live mode)
    KERNEL /boot/vmlinuz
    APPEND initrd=/boot/live-initramfs.img root=/dev/ram0 quiet splash desktop

LABEL lfs-live-persist
    MENU LABEL ^Try LFS Linux (with Persistence)
    KERNEL /boot/vmlinuz
    APPEND initrd=/boot/live-initramfs.img root=/dev/ram0 quiet splash desktop persistence

LABEL install
    MENU LABEL ^Install LFS Linux
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
BOOTMENU

# ============================================================================
# CREATE EFI BOOT IMAGE
# ============================================================================
log_info "Creating EFI boot image..."

dd if=/dev/zero of=$INSTALLER_DIR/boot/efi.img bs=1M count=20 2>/dev/null
mkfs.vfat $INSTALLER_DIR/boot/efi.img
mkdir -p $INSTALLER_DIR/efi/boot
mount -o loop $INSTALLER_DIR/boot/efi.img $INSTALLER_DIR/efi
cp -v $INSTALLER_DIR/boot/vmlinuz $INSTALLER_DIR/efi/boot/vmlinuz.efi
cp -v $INSTALLER_DIR/boot/initramfs.img $INSTALLER_DIR/efi/boot/initramfs.img
cp -v $INSTALLER_DIR/boot/live-initramfs.img $INSTALLER_DIR/efi/boot/live-initramfs.img
umount $INSTALLER_DIR/efi

# ============================================================================
# CREATE THE FINAL ISO
# ============================================================================
log_info "Creating ISO image..."

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

    SHA256SUM=$(sha256sum "../$ISO_NAME" | cut -d' ' -f1)
    echo "$SHA256SUM  $ISO_NAME" > "../$ISO_NAME.sha256"
    log_info "SHA256: $SHA256SUM"

    echo ""
    echo "=========================================="
    echo "  Live System Features:"
    echo "=========================================="
    echo "  ✓ Try LFS without installing"
    echo "  ✓ Persistence support (save changes)"
    echo "  ✓ Install to disk"
    echo "  ✓ Rescue mode"
    echo ""
    echo "To create persistence on USB after writing:"
    echo "  sudo create-persistence.sh /dev/sdX 4096"
else
    log_error "Failed to create ISO image"
    exit 1
fi

log_info "Installer creation complete!"