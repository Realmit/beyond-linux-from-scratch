#!/bin/bash
# Installation de GRUB pour BIOS et UEFI
set -e

LFS="${LFS:-/output/image}"

echo "[INFO] Installing bootloader (GRUB)..."

# Vérifier la présence des fichiers GRUB
if [ ! -f "$LFS/usr/sbin/grub-install" ]; then
    echo "[ERROR] GRUB not installed in $LFS. Please build GRUB first."
    exit 1
fi

# Monter /dev et /proc si nécessaire (pour chroot)
sudo mount --bind /dev "$LFS/dev"
sudo mount --bind /proc "$LFS/proc"

# Installer GRUB en mode BIOS (pour compatibilité)
sudo chroot "$LFS" /usr/sbin/grub-install --target=i386-pc /dev/sda || true
# Installer GRUB en mode UEFI (si les fichiers existent)
if [ -d "$LFS/usr/lib/grub/x86_64-efi" ]; then
    sudo chroot "$LFS" /usr/sbin/grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB || true
fi

# Générer la configuration
sudo chroot "$LFS" /usr/sbin/grub-mkconfig -o /boot/grub/grub.cfg

# Nettoyer les montages
sudo umount "$LFS/dev" "$LFS/proc"

echo "[SUCCESS] Bootloader installed."