#!/bin/bash
# final/14-create-installer.sh – Create hybrid ISO with grub-mkrescue (BIOS+UEFI)
# Author : Jean-Francois Landreville, landrevillejf@protonmail.com, 2026.
set -e

LFS="${LFS:-/mnt/lfs}"
if [ -z "$LFS" ] || [ ! -d "$LFS" ]; then
    echo "[ERROR] LFS directory '$LFS' not found"
    exit 1
fi

OUTPUT_DIR="$(dirname "$LFS")"
INSTALLER_ISO="${OUTPUT_DIR}/lfs-installer.iso"
ISO_ROOT="${OUTPUT_DIR}/iso-root"

echo "[INFO] Creating bootable ISO from $LFS"
echo "[INFO] Output: $INSTALLER_ISO"

# Check required tools
if ! command -v grub-mkrescue >/dev/null 2>&1; then
    echo "[ERROR] grub-mkrescue not found. Please install grub-pc-bin and grub-efi-amd64-bin."
    exit 1
fi
if ! command -v mksquashfs >/dev/null 2>&1; then
    echo "[ERROR] mksquashfs not found. Please install squashfs-tools."
    exit 1
fi

# Locate kernel and initramfs
KERNEL=$(ls -1 "$LFS/boot/vmlinuz"* 2>/dev/null | head -n1)
if [ -z "$KERNEL" ]; then
    KERNEL=$(find "$LFS/boot" -name "vmlinuz*" -type f | head -n1)
fi
INITRAMFS=$(ls -1 "$LFS/boot/initramfs.img" 2>/dev/null | head -n1)
if [ -z "$INITRAMFS" ]; then
    INITRAMFS=$(find "$LFS/boot" -name "initramfs*" -type f | head -n1)
fi

if [ -z "$KERNEL" ] || [ -z "$INITRAMFS" ]; then
    echo "[ERROR] Kernel or initramfs not found in $LFS/boot"
    echo "  Kernel: ${KERNEL:-not found}"
    echo "  Initramfs: ${INITRAMFS:-not found}"
    exit 1
fi

echo "[INFO] Kernel: $KERNEL"
echo "[INFO] Initramfs: $INITRAMFS"

# Prepare ISO root
rm -rf "$ISO_ROOT"
mkdir -p "$ISO_ROOT/boot/grub"

cp -v "$KERNEL" "$ISO_ROOT/boot/vmlinuz"
cp -v "$INITRAMFS" "$ISO_ROOT/boot/initramfs.img"

# Create squashfs
echo "[INFO] Creating squashfs..."
mksquashfs "$LFS" "$ISO_ROOT/live.squashfs" -comp xz -noappend

# Write GRUB config using echo to avoid heredoc issues
mkdir -p "$ISO_ROOT/boot/grub"
{
    echo 'set timeout=10'
    echo 'set default=0'
    echo 'menuentry "LFS Linux Live" {'
    echo '    linux /boot/vmlinuz root=/dev/loop0 ro quiet'
    echo '    initrd /boot/initramfs.img'
    echo '}'
    echo 'menuentry "Install LFS Linux" {'
    echo '    linux /boot/vmlinuz root=/dev/loop0 ro quiet install'
    echo '    initrd /boot/initramfs.img'
    echo '}'
} > "$ISO_ROOT/boot/grub/grub.cfg"

# Build hybrid ISO with grub-mkrescue
echo "[INFO] Building hybrid ISO with grub-mkrescue..."
grub-mkrescue -o "$INSTALLER_ISO" "$ISO_ROOT"

rm -rf "$ISO_ROOT"
echo "[SUCCESS] ISO created at $INSTALLER_ISO"
ls -lh "$INSTALLER_ISO"