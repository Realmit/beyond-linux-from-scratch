#!/bin/bash
# Création d'un système live avec squashfs et ISO hybride
set -e

LFS="${LFS:-/output/image}"
OUTPUT_DIR="$(dirname "$LFS")"
SQUASHFS="${OUTPUT_DIR}/live.squashfs"
ISO_OUT="${OUTPUT_DIR}/lfs-installer.iso"

echo "[INFO] Creating live system (squashfs + ISO)..."

if ! command -v mksquashfs &>/dev/null; then
    echo "[ERROR] mksquashfs not found. Install squashfs-tools."
    exit 1
fi

# Créer le squashfs (en excluant les répertoires virtuels)
mksquashfs "$LFS" "$SQUASHFS" \
    -comp xz -Xbcj x86 -b 1M \
    -wildcards -e "proc/*" "sys/*" "dev/*" "run/*" "tmp/*" "sources/*"

# Préparer le contenu de l'ISO
ISO_DIR="${OUTPUT_DIR}/iso-content"
rm -rf "$ISO_DIR"
mkdir -pv "$ISO_DIR"/{isolinux,boot/grub,EFI/BOOT}

# Copier le noyau et l'initramfs depuis le rootfs
cp -v "$LFS/boot/vmlinuz-"* "$ISO_DIR/isolinux/vmlinuz" || \
    { echo "[ERROR] Kernel not found in $LFS/boot"; exit 1; }
cp -v "$LFS/boot/initramfs.img" "$ISO_DIR/isolinux/initrd.img" || \
    { echo "[ERROR] Initramfs not found"; exit 1; }

# Copier le squashfs
cp -v "$SQUASHFS" "$ISO_DIR/live.squashfs"

# Copier isolinux et configuration
cp -v /usr/lib/ISOLINUX/isolinux.bin "$ISO_DIR/isolinux/" || \
    cp -v /usr/lib/syslinux/isolinux.bin "$ISO_DIR/isolinux/" || \
    { echo "[ERROR] isolinux.bin not found"; exit 1; }
cp -v /usr/lib/syslinux/modules/bios/*.c32 "$ISO_DIR/isolinux/" || true

cat > "$ISO_DIR/isolinux/isolinux.cfg" << 'EOF'
default live
label live
  kernel vmlinuz
  append initrd=initrd.img root=/dev/sr0 ro quiet
label live-verbose
  kernel vmlinuz
  append initrd=initrd.img root=/dev/sr0 ro
EOF

# Pour UEFI, copier un bootloader (ex: grub)
if [ -d "$LFS/usr/lib/grub/x86_64-efi" ]; then
    cp -r "$LFS/usr/lib/grub/x86_64-efi"/* "$ISO_DIR/EFI/BOOT/"
    cp -v "$LFS/boot/efi/EFI/BOOT/BOOTX64.EFI" "$ISO_DIR/EFI/BOOT/" || true
fi

# Générer l'ISO avec xorriso
if ! command -v xorriso &>/dev/null; then
    echo "[ERROR] xorriso not found. Install xorriso."
    exit 1
fi

xorriso -as mkisofs \
    -r -V "LFS_LIVE" \
    -J -joliet-long \
    -cache-inodes \
    -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
    -b isolinux/isolinux.bin \
    -c isolinux/boot.cat \
    -boot-load-size 4 -boot-info-table -no-emul-boot \
    -eltorito-alt-boot -e EFI/BOOT/BOOTX64.EFI -no-emul-boot \
    -isohybrid-gpt-basdat \
    -o "$ISO_OUT" "$ISO_DIR"

# Nettoyer
rm -rf "$ISO_DIR" "$SQUASHFS"

echo "[SUCCESS] Live ISO created at $ISO_OUT"
ls -lh "$ISO_OUT"