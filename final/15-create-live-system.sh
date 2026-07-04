#!/bin/bash
# Create a live system with squashfs and hybrid ISO (BIOS+UEFI)
# Author: Jean-Francois Landreville, landrevillejf@protonmail.com, 2026.
set -e

LFS="${LFS:-/output/image}"
OUTPUT_DIR="$(dirname "$LFS")"
SQUASHFS="${OUTPUT_DIR}/live.squashfs"
ISO_OUT="${OUTPUT_DIR}/lfs-installer.iso"

echo "[INFO] Creating live system (squashfs + ISO)..."

# Check required tools
for tool in mksquashfs xorriso; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "[ERROR] $tool not found. Please install it."
        exit 1
    fi
done

# Find kernel and initramfs
KERNEL=$(ls -1 "$LFS/boot/vmlinuz-"* 2>/dev/null | head -1)
if [ -z "$KERNEL" ]; then
    echo "[ERROR] Kernel not found in $LFS/boot"
    exit 1
fi
INITRAMFS="$LFS/boot/initramfs.img"
if [ ! -f "$INITRAMFS" ]; then
    echo "[ERROR] Initramfs not found: $INITRAMFS"
    exit 1
fi

echo "[INFO] Kernel: $KERNEL"
echo "[INFO] Initramfs: $INITRAMFS"

# Create squashfs (excluding virtual filesystems)
echo "[INFO] Creating squashfs..."
mksquashfs "$LFS" "$SQUASHFS" \
    -comp xz -Xbcj x86 -b 1M \
    -wildcards -e "proc/*" "sys/*" "dev/*" "run/*" "tmp/*" "sources/*"

# Prepare ISO content
ISO_DIR="${OUTPUT_DIR}/iso-content"
rm -rf "$ISO_DIR"
mkdir -pv "$ISO_DIR"/{isolinux,boot/grub,EFI/BOOT}

# Copy kernel and initramfs
cp -v "$KERNEL" "$ISO_DIR/isolinux/vmlinuz"
cp -v "$INITRAMFS" "$ISO_DIR/isolinux/initrd.img"

# Copy squashfs
cp -v "$SQUASHFS" "$ISO_DIR/live.squashfs"

# Copy isolinux binary
ISOLINUX_BIN="/usr/lib/ISOLINUX/isolinux.bin"
[ -f "$ISOLINUX_BIN" ] || ISOLINUX_BIN="/usr/lib/syslinux/isolinux.bin"
if [ ! -f "$ISOLINUX_BIN" ]; then
    echo "[ERROR] isolinux.bin not found"
    exit 1
fi
cp -v "$ISOLINUX_BIN" "$ISO_DIR/isolinux/"

# Copy isolinux modules (optional)
if [ -d "/usr/lib/syslinux/modules/bios" ]; then
    cp -v /usr/lib/syslinux/modules/bios/*.c32 "$ISO_DIR/isolinux/" 2>/dev/null || true
fi

# ISOLINUX configuration
cat > "$ISO_DIR/isolinux/isolinux.cfg" << 'EOF'
default live
label live
  kernel vmlinuz
  append initrd=initrd.img root=/dev/sr0 ro quiet
label live-verbose
  kernel vmlinuz
  append initrd=initrd.img root=/dev/sr0 ro
EOF

# EFI support – only if the EFI bootloader exists
EFI_FILE="$LFS/boot/efi/EFI/BOOT/BOOTX64.EFI"
if [ -f "$EFI_FILE" ]; then
    echo "[INFO] Found EFI bootloader, including UEFI support"
    cp -v "$EFI_FILE" "$ISO_DIR/EFI/BOOT/"
    EFI_OPTION="-eltorito-alt-boot -e EFI/BOOT/BOOTX64.EFI -no-emul-boot -isohybrid-gpt-basdat"
else
    echo "[WARNING] No EFI bootloader found – building BIOS-only ISO"
    EFI_OPTION=""
fi

# Generate ISO with xorriso (using -iso-level 4 for large files)
echo "[INFO] Building ISO..."
xorriso -as mkisofs \
    -iso-level 4 \
    -r -V "LFS_LIVE" \
    -J -joliet-long \
    -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
    -b isolinux/isolinux.bin \
    -c isolinux/boot.cat \
    -boot-load-size 4 -boot-info-table -no-emul-boot \
    $EFI_OPTION \
    -o "$ISO_OUT" "$ISO_DIR"

# Clean up
rm -rf "$ISO_DIR" "$SQUASHFS"

echo "[SUCCESS] Live ISO created at $ISO_OUT"
ls -lh "$ISO_OUT"