#!/bin/bash
# Create complete live system with persistence support

source scripts/common/utils.sh

log_info "Creating live system environment"

# ============================================================================
# CREATE SQUASHFS OF ROOT FILESYSTEM
# ============================================================================
create_live_squashfs() {
    log_info "Creating compressed live filesystem (squashfs)..."

    # Create live system directory
    mkdir -p $LFS/live/{rootfs,overlay,persistence}

    # Create squashfs of the root filesystem
    mksquashfs $LFS $LFS/live/rootfs/lfs.squashfs \
        -comp xz \
        -b 1M \
        -noappend \
        -progress

    log_success "Live squashfs created"
}

# ============================================================================
# CREATE PERSISTENCE SUPPORT
# ============================================================================
create_persistence() {
    log_info "Setting up persistence support..."

    # Create overlay directories
    mkdir -p $LFS/live/overlay/{upper,work}

    # Create script for persistence mount
    cat > $LFS/live/persistence-setup.sh << 'EOF'
#!/bin/bash
# Setup persistence for live system

PERSISTENCE_LABEL="LFS-PERSIST"

# Check for persistence partition
check_persistence() {
    for dev in /dev/sd* /dev/nvme*; do
        if [ -b "$dev" ]; then
            LABEL=$(blkid -s LABEL -o value "$dev" 2>/dev/null)
            if [ "$LABEL" = "$PERSISTENCE_LABEL" ]; then
                echo "$dev"
                return 0
            fi
        fi
    done
    return 1
}

# Setup overlay if persistence found
setup_persistence() {
    PERSIST_DEV=$(check_persistence)
    if [ -n "$PERSIST_DEV" ]; then
        echo "Found persistence partition on $PERSIST_DEV"
        mount "$PERSIST_DEV" /mnt/persistence
        mkdir -p /mnt/persistence/{upper,work}

        # Mount overlay filesystem
        mount -t overlay overlay \
            -o lowerdir=/run/rootfs,upperdir=/mnt/persistence/upper,workdir=/mnt/persistence/work \
            /mnt/root

        echo "Persistence enabled"
    fi
}

# Main
setup_persistence
EOF
    chmod +x $LFS/live/persistence-setup.sh

    log_success "Persistence configured"
}

# ============================================================================
# CREATE LIVE INITRAMFS
# ============================================================================
create_live_initramfs() {
    log_info "Creating live initramfs..."

    cat > $LFS/live/init << 'EOF'
#!/bin/busybox sh

# Live system init script

# Mount basic filesystems
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev

# Detect live media
detect_live_media() {
    for dev in /dev/sr0 /dev/sd* /dev/nvme*; do
        if [ -b "$dev" ] && mount "$dev" /mnt 2>/dev/null; then
            if [ -f /mnt/live/rootfs/lfs.squashfs ]; then
                LIVE_MOUNT="/mnt"
                return 0
            fi
            umount /mnt
        fi
    done
    return 1
}

# Mount squashfs
mount_squashfs() {
    # Mount squashfs image
    mount -t squashfs "$LIVE_MOUNT/live/rootfs/lfs.squashfs" /run/rootfs

    # Setup overlay for writable root
    mkdir -p /run/overlay/{upper,work}
    mount -t overlay overlay \
        -o lowerdir=/run/rootfs,upperdir=/run/overlay/upper,workdir=/run/overlay/work \
        /mnt/root

    # Try to setup persistence if available
    if [ -f "$LIVE_MOUNT/live/persistence-setup.sh" ]; then
        sh "$LIVE_MOUNT/live/persistence-setup.sh"
    fi
}

# Start Xorg if requested
start_desktop() {
    if [ "$1" = "live" ]; then
        if [ -f /usr/bin/startx ]; then
            startx &
        fi
    fi
}

# Main
detect_live_media
mount_squashfs

# Switch to live root
exec switch_root /mnt/root /sbin/init

# Check for desktop mode
if grep -q "live" /proc/cmdline; then
    start_desktop "live"
fi
EOF

    chmod +x $LFS/live/init

    # Add to initramfs
    cd $LFS/live
    find . -name "init" -o -name "*.sh" | cpio -o -H newc | gzip > $LFS/boot/live-initramfs.img

    log_success "Live initramfs created"
}

# ============================================================================
# CREATE PERSISTENCE TOOL
# ============================================================================
create_persistence_tool() {
    log_info "Creating persistence setup tool..."

    cat > $LFS/usr/local/sbin/create-persistence.sh << 'EOF'
#!/bin/bash
# Create persistence partition for live system

PERSISTENCE_SIZE=${1:-2048}  # Size in MB
PERSISTENCE_DEV=""

select_device() {
    echo "Available devices:"
    lsblk -d -o NAME,SIZE,MODEL
    echo
    read -p "Select device for persistence (e.g., sdb): " PERSISTENCE_DEV
    PERSISTENCE_DEV="/dev/$PERSISTENCE_DEV"
}

create_persistence() {
    echo "Creating persistence partition of ${PERSISTENCE_SIZE}MB on $PERSISTENCE_DEV"

    # Create partition
    parted -s $PERSISTENCE_DEV mkpart primary ext4 ${PERSISTENCE_SIZE}MiB 100%

    # Format with label
    mkfs.ext4 -F -L LFS-PERSIST ${PERSISTENCE_DEV}1

    # Create necessary directories
    mount ${PERSISTENCE_DEV}1 /mnt
    mkdir -p /mnt/{upper,work}
    umount /mnt

    echo "Persistence partition created!"
    echo "Label: LFS-PERSIST"
    echo "Size: ${PERSISTENCE_SIZE}MB"
}

main() {
    select_device
    create_persistence
}

main "$@"
EOF

    chmod +x $LFS/usr/local/sbin/create-persistence.sh

    log_success "Persistence tool created"
}

# ============================================================================
# UPDATE INSTALLER FOR LIVE MODE
# ============================================================================
update_installer_for_live() {
    log_info "Updating installer for live mode..."

    # Add live mode detection to installer
    cat >> $LFS/usr/sbin/lfs-installer << 'EOF'

# Detect if running in live mode
if [ -f /run/.live-system ]; then
    LIVE_MODE=true
else
    LIVE_MODE=false
fi

# Live mode specific menu
if [ "$LIVE_MODE" = true ]; then
    echo ""
    echo "Running in LIVE mode with persistence support"
    echo "Your changes will be saved if persistence is enabled"
    echo ""
fi
EOF

    log_success "Installer updated"
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    log_info "=== CREATING LIVE SYSTEM ==="

    create_live_squashfs
    create_persistence
    create_live_initramfs
    create_persistence_tool
    update_installer_for_live

    log_success "Live system created successfully!"
    echo ""
    echo "Live system features:"
    echo "  ✓ Compressed root filesystem (squashfs)"
    echo "  ✓ RAM-based operation"
    echo "  ✓ Persistence support (optional)"
    echo "  ✓ 'try before install' mode"
    echo ""
    echo "To use persistence:"
    echo "  Run 'create-persistence.sh' on a USB drive"
}

main "$@"