#!/bin/bash
# Installation de GRUB pour BIOS et UEFI
set -e

LFS="${LFS:-/output/image}"

echo "[INFO] Installing bootloader (GRUB)..."

if [ ! -f "$LFS/usr/sbin/grub-install" ]; then
    echo "[ERROR] GRUB not installed in $LFS. Please build GRUB first."
    exit 1
fi

# Monter /dev, /proc, /sys pour le chroot
mount --bind /dev "$LFS/dev"
mount --bind /proc "$LFS/proc"
mount --bind /sys "$LFS/sys"

# Installer GRUB en mode BIOS
chroot "$LFS" /usr/sbin/grub-install --target=i386-pc /dev/sda || true
# Installer GRUB en mode UEFI
if [ -d "$LFS/usr/lib/grub/x86_64-efi" ]; then
    chroot "$LFS" /usr/sbin/grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB || true
fi

# Générer la configuration
chroot "$LFS" /usr/sbin/grub-mkconfig -o /boot/grub/grub.cfg

# Nettoyer les montages
umount "$LFS/dev" "$LFS/proc" "$LFS/sys"

echo "[SUCCESS] Bootloader installed."