#!/bin/bash
set -e
LFS=${LFS:-/mnt/lfs}
# Montages
mount --bind /dev $LFS/dev
mount -t devpts devpts $LFS/dev/pts
mount -t proc proc $LFS/proc
mount -t sysfs sysfs $LFS/sys

chroot "$LFS" /bin/bash << 'EOF'
cd /sources
KERNEL_VERSION=$(ls -1 linux-*.tar.xz | head -n1 | sed 's/linux-//;s/\.tar\.xz//')
tar -xf linux-*.tar.xz
cd linux-*
make mrproper
make defconfig
make -j$(nproc)
make modules_install
cp arch/x86/boot/bzImage /boot/vmlinuz
cp System.map /boot/System.map
EOF

umount $LFS/dev/pts $LFS/dev $LFS/proc $LFS/sys