#!/bin/bash
# Create disk image for USB installation

source scripts/common/utils.sh

IMAGE_SIZE_MB=${IMAGE_SIZE_MB:-8192}
BOOT_SIZE_MB=512
SWAP_SIZE_MB=2048
ROOT_SIZE_MB=$((IMAGE_SIZE_MB - BOOT_SIZE_MB - SWAP_SIZE_MB))

log_info "Creating disk image of ${IMAGE_SIZE_MB}MB"

# Create empty image file
dd if=/dev/zero of=$LFS.img bs=1M count=$IMAGE_SIZE_MB status=progress

# Setup loop device
LOOP_DEV=$(losetup --find --show --partscan $LFS.img)

# Create partition table
parted -s $LOOP_DEV mklabel gpt
parted -s $LOOP_DEV mkpart primary fat32 1MiB ${BOOT_SIZE_MB}MiB
parted -s $LOOP_DEV mkpart primary linux-swap ${BOOT_SIZE_MB}MiB $((BOOT_SIZE_MB + SWAP_SIZE_MB))MiB
parted -s $LOOP_DEV mkpart primary ext4 $((BOOT_SIZE_MB + SWAP_SIZE_MB))MiB 100%
parted -s $LOOP_DEV set 1 esp on

# Wait for partitions to appear
sleep 2

# Format partitions
mkfs.vfat -F32 ${LOOP_DEV}p1
mkswap ${LOOP_DEV}p2
mkfs.ext4 -F ${LOOP_DEV}p3

# Mount partitions
mkdir -pv $LFS
mount ${LOOP_DEV}p3 $LFS
mkdir -pv $LFS/boot
mount ${LOOP_DEV}p1 $LFS/boot
swapon ${LOOP_DEV}p2

log_info "Disk image created and mounted at $LFS"
log_info "Loop device: $LOOP_DEV"
echo $LOOP_DEV > /tmp/lfs_loop_device
