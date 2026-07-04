#!/bin/bash
# final/14-create-installer.sh – Generate a bootable hybrid ISO with installer
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

# ---------------------------------------------------------------------------
# Check required tools
# ---------------------------------------------------------------------------
check_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "[ERROR] $1 not found. Please install it."
        echo "  Ubuntu: apt-get install xorriso squashfs-tools isolinux"
        exit 1
    fi
}
check_tool xorriso
check_tool mksquashfs
check_tool isolinux

# ---------------------------------------------------------------------------
# Locate kernel and initramfs
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Prepare ISO root
# ---------------------------------------------------------------------------
rm -rf "$ISO_ROOT"
mkdir -p "$ISO_ROOT"/{boot/grub,isolinux,EFI/BOOT}

cp -v "$KERNEL" "$ISO_ROOT/boot/vmlinuz"
cp -v "$INITRAMFS" "$ISO_ROOT/boot/initramfs.img"

echo "[INFO] Creating squashfs..."
mksquashfs "$LFS" "$ISO_ROOT/live.squashfs" -comp xz -noappend

# ---------------------------------------------------------------------------
# GRUB configuration
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# ISOLINUX configuration
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Build ISO with xorriso
# ---------------------------------------------------------------------------
echo "[INFO] Building ISO with xorriso..."

ISOHDPFX="/usr/lib/ISOLINUX/isohdpfx.bin"
if [ ! -f "$ISOHDPFX" ]; then
    ISOHDPFX=$(find /usr -name "isohdpfx.bin" 2>/dev/null | head -n1)
    if [ -z "$ISOHDPFX" ]; then
        echo "[WARNING] isohdpfx.bin not found; BIOS hybrid boot may not work"
        ISOHDPFX=""
    fi
fi

xorriso -as mkisofs \
    -V "LFS_LINUX" \
    -R -J -joliet-long \
    -cache-inodes \
    ${ISOHDPFX:+-isohybrid-mbr "$ISOHDPFX"} \
    -b isolinux/isolinux.bin \
    -c isolinux/boot.cat \
    -boot-load-size 4 -boot-info-table -no-emul-boot \
    -eltorito-alt-boot -e EFI/BOOT/BOOTX64.EFI -no-emul-boot \
    -isohybrid-gpt-basdat \
    -o "$INSTALLER_ISO" "$ISO_ROOT"

rm -rf "$ISO_ROOT"
echo "[SUCCESS] ISO created at $INSTALLER_ISO"
ls -lh "$INSTALLER_ISO"