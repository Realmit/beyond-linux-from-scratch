#!/bin/bash
set -e
LFS=${LFS:-/output/image}
mkdir -pv $LFS/boot/grub
touch $LFS/boot/grub/grub.cfg
echo "grub.cfg placeholder" > $LFS/boot/grub/grub.cfg
exit 0
