#!/bin/bash
# Initramfs - Docker compatible minimal
set -e
LFS=${LFS:-/output/image}
echo "[INFO] Creating initramfs skeleton (Docker mode)"
mkdir -pv $LFS/boot
touch $LFS/boot/initramfs.img
echo "[SUCCESS] Initramfs skeleton created"
exit 0
