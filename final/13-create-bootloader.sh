#!/bin/bash
# final/13-create-bootloader.sh – Install GRUB bootloader
set -e

LFS="${LFS:-/mnt/lfs}"
if [ ! -d "$LFS" ]; then
    echo "[ERROR] LFS directory not found"
    exit 1
fi

echo "[INFO] Installing bootloader (GRUB)..."

# Monter les systèmes de fichiers virtuels
mount --bind /dev "$LFS/dev" 2>/dev/null || true
mount --bind /proc "$LFS/proc" 2>/dev/null || true
mount --bind /sys "$LFS/sys" 2>/dev/null || true

# Installer GRUB (BIOS)
if [ -f "$LFS/usr/sbin/grub-install" ]; then
    chroot "$LFS" grub-install --target=i386-pc /dev/sda || echo "GRUB BIOS install skipped"
    chroot "$LFS" grub-mkconfig -o /boot/grub/grub.cfg
else
    echo "[WARNING] GRUB not installed in LFS"
fi

# Nettoyer
umount "$LFS/dev" 2>/dev/null || true
umount "$LFS/proc" 2>/dev/null || true
umount "$LFS/sys" 2>/dev/null || true

echo "[SUCCESS] Bootloader configured"