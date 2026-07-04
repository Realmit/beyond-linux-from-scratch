#!/bin/bash
# final/14-create-installer.sh – ISO hybride BIOS/UEFI avec xorriso direct
# Author : Jean-Francois Landreville, landrevillejf@protonmail.com, 2026.
set -e

# Re‑launch with sudo if not root
if [ "$EUID" -ne 0 ]; then
    echo "[INFO] Relaunching with sudo..."
    exec sudo -E "$0" "$@"
fi

LFS="${LFS:-/mnt/lfs}"
if [ -z "$LFS" ] || [ ! -d "$LFS" ]; then
    echo "[ERROR] LFS directory '$LFS' not found"
    exit 1
fi

OUTPUT_DIR="$(dirname "$LFS")"
INSTALLER_ISO="${OUTPUT_DIR}/lfs-installer.iso"
ISO_ROOT="${OUTPUT_DIR}/iso-root"
EFI_IMG="${OUTPUT_DIR}/efi.img"

echo "[INFO] Creating bootable ISO from $LFS"
echo "[INFO] Output: $INSTALLER_ISO"

# Check required tools
for tool in xorriso mksquashfs grub-install mkfs.vfat mount; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "[ERROR] $tool not found. Please install."
        exit 1
    fi
done

# Find kernel and initramfs
KERNEL=$(ls -1 "$LFS/boot/vmlinuz"* 2>/dev/null | head -n1)
[ -z "$KERNEL" ] && KERNEL=$(find "$LFS/boot" -name "vmlinuz*" -type f | head -n1)
INITRAMFS=$(ls -1 "$LFS/boot/initramfs.img" 2>/dev/null | head -n1)
[ -z "$INITRAMFS" ] && INITRAMFS=$(find "$LFS/boot" -name "initramfs*" -type f | head -n1)

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
mkdir -p "$ISO_ROOT"/{boot/grub,isolinux,EFI/BOOT}

cp -v "$KERNEL" "$ISO_ROOT/boot/vmlinuz"
cp -v "$INITRAMFS" "$ISO_ROOT/boot/initramfs.img"

# Create squashfs (may exceed 4 GiB)
echo "[INFO] Creating squashfs..."
mksquashfs "$LFS" "$ISO_ROOT/live.squashfs" -comp xz -noappend

# GRUB config (used by both BIOS and UEFI)
cat > "$ISO_ROOT/boot/grub/grub.cfg" << 'EOF'
set timeout=10
set default=0
menuentry "LFS Linux Live" {
    linux /boot/vmlinuz root=/dev/loop0 ro quiet
    initrd /boot/initramfs.img
}
menuentry "Install LFS Linux" {
    linux /boot/vmlinuz root=/dev/loop0 ro quiet install
    initrd /boot/initramfs.img
}
EOF

# --- Create EFI boot image (FAT with GRUB) ---
echo "[INFO] Creating EFI boot image..."
EFI_MOUNT="${OUTPUT_DIR}/efi-mount"
mkdir -p "$EFI_MOUNT"

# 64 MiB FAT image
dd if=/dev/zero of="$EFI_IMG" bs=1M count=64 2>/dev/null
mkfs.vfat "$EFI_IMG" 2>/dev/null
mount -o loop "$EFI_IMG" "$EFI_MOUNT"

# Install GRUB for EFI into the image
grub-install --target=x86_64-efi \
    --efi-directory="$EFI_MOUNT" \
    --boot-directory="$EFI_MOUNT/boot" \
    --removable \
    --modules="part_gpt fat" \
    --no-floppy

# Copy our grub.cfg
mkdir -p "$EFI_MOUNT/boot/grub"
cp "$ISO_ROOT/boot/grub/grub.cfg" "$EFI_MOUNT/boot/grub/"

# Unmount and clean up
umount "$EFI_MOUNT"
rmdir "$EFI_MOUNT"

# Copy the EFI image into the ISO
cp "$EFI_IMG" "$ISO_ROOT/EFI/BOOT/BOOTX64.EFI"

# --- Prepare ISOLINUX for BIOS boot ---
cp /usr/lib/ISOLINUX/isolinux.bin "$ISO_ROOT/isolinux/"
cp /usr/lib/ISOLINUX/isohdpfx.bin "$ISO_ROOT/isolinux/" 2>/dev/null || true

cat > "$ISO_ROOT/isolinux/isolinux.cfg" << 'EOF'
default live
timeout 10
label live
    kernel /boot/vmlinuz
    append initrd=/boot/initramfs.img root=/dev/loop0 ro quiet
label install
    kernel /boot/vmlinuz
    append initrd=/boot/initramfs.img root=/dev/loop0 ro quiet install
EOF

# --- Build ISO with xorriso (ISO level 4 for large files) ---
echo "[INFO] Building ISO with xorriso (BIOS+UEFI, ISO level 4)..."
xorriso -as mkisofs \
    -iso-level 4 \
    -V "LFS_LINUX" \
    -R -J -joliet-long \
    -cache-inodes \
    -isohybrid-mbr "$ISO_ROOT/isolinux/isohdpfx.bin" \
    -b isolinux/isolinux.bin \
    -c isolinux/boot.cat \
    -boot-load-size 4 -boot-info-table -no-emul-boot \
    -eltorito-alt-boot -e EFI/BOOT/BOOTX64.EFI -no-emul-boot \
    -isohybrid-gpt-basdat \
    -o "$INSTALLER_ISO" "$ISO_ROOT"

# Clean up
rm -rf "$ISO_ROOT" "$EFI_IMG"
echo "[SUCCESS] ISO created at $INSTALLER_ISO"
ls -lh "$INSTALLER_ISO"