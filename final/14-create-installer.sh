#!/bin/bash
# final/14-create-installer.sh – Hybrid BIOS/UEFI ISO with aggressive size reduction
set -e

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

# ---------------------------------------------------------------------------
# 1. Aggressive size reduction (keep kernel and initramfs)
# ---------------------------------------------------------------------------
echo "[INFO] Stripping binaries and libraries..."
find "$LFS" -type f -executable -exec strip --strip-unneeded {} \; 2>/dev/null || true
find "$LFS" -name "*.so*" -exec strip --strip-unneeded {} \; 2>/dev/null || true

echo "[INFO] Removing unnecessary files..."
rm -rf "$LFS/sources" "$LFS/usr/share/doc" "$LFS/usr/share/man" "$LFS/usr/share/info"
rm -rf "$LFS/usr/share/locale" "$LFS/usr/share/help" "$LFS/usr/share/backgrounds"
rm -rf "$LFS/var/cache/*" "$LFS/var/log/*" "$LFS/var/lib/lpm"
# DO NOT delete the kernel! Keep it for the ISO.
# rm -rf "$LFS/boot/vmlinuz-*"   # <-- REMOVED
rm -rf "$LFS/lib/modules/*/source" "$LFS/lib/modules/*/build"

# Keep only en_US.UTF-8 locale
if [ -d "$LFS/usr/lib/locale" ]; then
    find "$LFS/usr/lib/locale" -mindepth 1 -maxdepth 1 -type d ! -name "en_US.UTF-8" -exec rm -rf {} \; 2>/dev/null || true
fi

# Keep only Adwaita and hicolor icons
if [ -d "$LFS/usr/share/icons" ]; then
    for theme in Adwaita hicolor; do
        find "$LFS/usr/share/icons" -mindepth 1 -maxdepth 1 -type d ! -name "$theme" -exec rm -rf {} \; 2>/dev/null || true
    done
fi

# ---------------------------------------------------------------------------
# 2. Disk space check
# ---------------------------------------------------------------------------
LFS_SIZE_GB=$(du -sk "$LFS" | awk '{print $1/1024/1024}')
REQUIRED_GB=$(echo "$LFS_SIZE_GB * 1.2 + 2" | bc | cut -d. -f1)
AVAILABLE_GB=$(df --output=avail -BG "$OUTPUT_DIR" | tail -1 | tr -d 'G' | tr -d ' ')

if [ "$AVAILABLE_GB" -lt "$REQUIRED_GB" ]; then
    echo "[ERROR] Insufficient disk space after cleanup."
    echo "  Required: ~${REQUIRED_GB} GB (estimated)"
    echo "  Available: ${AVAILABLE_GB} GB"
    exit 1
fi
echo "[INFO] Disk space check passed (${AVAILABLE_GB} GB available)."

# ---------------------------------------------------------------------------
# 3. Check tools
# ---------------------------------------------------------------------------
for tool in xorriso mksquashfs grub-install mkfs.vfat mount; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "[ERROR] $tool not found."
        exit 1
    fi
done

# ---------------------------------------------------------------------------
# 4. Find kernel and initramfs – prefer versioned files
# ---------------------------------------------------------------------------
KERNEL=$(ls -1 "$LFS/boot/vmlinuz-"* 2>/dev/null | head -1)
if [ -z "$KERNEL" ]; then
    KERNEL=$(ls -1 "$LFS/boot/vmlinuz" 2>/dev/null | head -1)
fi
if [ -z "$KERNEL" ]; then
    echo "[ERROR] No kernel found in $LFS/boot"
    exit 1
fi

INITRAMFS=$(ls -1 "$LFS/boot/initramfs.img" 2>/dev/null | head -1)
if [ -z "$INITRAMFS" ]; then
    INITRAMFS=$(find "$LFS/boot" -name "initramfs*" -type f | head -1)
fi
if [ -z "$INITRAMFS" ]; then
    echo "[ERROR] Initramfs not found in $LFS/boot"
    exit 1
fi

echo "[INFO] Kernel: $KERNEL"
echo "[INFO] Initramfs: $INITRAMFS"

# ---------------------------------------------------------------------------
# 5. Prepare ISO root and squashfs
# ---------------------------------------------------------------------------
rm -rf "$ISO_ROOT"
mkdir -p "$ISO_ROOT"/{boot/grub,isolinux,EFI/BOOT}

cp -v "$KERNEL" "$ISO_ROOT/boot/vmlinuz"
cp -v "$INITRAMFS" "$ISO_ROOT/boot/initramfs.img"

echo "[INFO] Creating squashfs..."
mksquashfs "$LFS" "$ISO_ROOT/live.squashfs" \
    -comp xz -Xbcj x86 -b 1M \
    -wildcards \
    -e "proc/*" "sys/*" "dev/*" "run/*" "tmp/*" \
       "sources/*" "usr/share/doc/*" "usr/share/man/*" "usr/share/info/*" \
       "usr/share/locale/*" "usr/share/help/*" "usr/share/backgrounds/*" \
       "usr/share/icons/*" "var/cache/*" "var/log/*" "var/lib/lpm/*" \
       "lib/modules/*/source" "lib/modules/*/build"

# ---------------------------------------------------------------------------
# 6. GRUB config
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
# 7. EFI boot image
# ---------------------------------------------------------------------------
echo "[INFO] Creating EFI boot image..."
EFI_MOUNT="${OUTPUT_DIR}/efi-mount"
mkdir -p "$EFI_MOUNT"

dd if=/dev/zero of="$EFI_IMG" bs=1M count=64 2>/dev/null
mkfs.vfat "$EFI_IMG" 2>/dev/null
mount -o loop "$EFI_IMG" "$EFI_MOUNT"

grub-install --target=x86_64-efi \
    --efi-directory="$EFI_MOUNT" \
    --boot-directory="$EFI_MOUNT/boot" \
    --removable \
    --modules="part_gpt fat" \
    --no-floppy

mkdir -p "$EFI_MOUNT/boot/grub"
cp "$ISO_ROOT/boot/grub/grub.cfg" "$EFI_MOUNT/boot/grub/"

umount "$EFI_MOUNT"
rmdir "$EFI_MOUNT"
cp "$EFI_IMG" "$ISO_ROOT/EFI/BOOT/BOOTX64.EFI"

# ---------------------------------------------------------------------------
# 8. ISOLINUX for BIOS
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# 9. Build ISO with xorriso
# ---------------------------------------------------------------------------
echo "[INFO] Building ISO..."
xorriso -as mkisofs \
    -iso-level 4 \
    -V "LFS_LINUX" \
    -R -J -joliet-long \
    -isohybrid-mbr "$ISO_ROOT/isolinux/isohdpfx.bin" \
    -b isolinux/isolinux.bin \
    -c isolinux/boot.cat \
    -boot-load-size 4 -boot-info-table -no-emul-boot \
    -eltorito-alt-boot -e EFI/BOOT/BOOTX64.EFI -no-emul-boot \
    -isohybrid-gpt-basdat \
    -o "$INSTALLER_ISO" "$ISO_ROOT"

# ---------------------------------------------------------------------------
# 10. Clean up
# ---------------------------------------------------------------------------
rm -rf "$ISO_ROOT" "$EFI_IMG"
echo "[SUCCESS] ISO created at $INSTALLER_ISO"
ls -lh "$INSTALLER_ISO"