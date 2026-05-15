#!/bin/bash
# Configure bootloader

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/utils.sh"

log_info "Configuring bootloader"

cat > $LFS/configure-bootloader.sh << "EOF"
#!/bin/bash

set -e

# GRUB configuration
cat > /boot/grub/grub.cfg << "GRUBCFG"
# Begin /boot/grub/grub.cfg
set default=0
set timeout=5

insmod part_gpt
insmod ext2
insmod fat

if [ -f /boot/grub/grubenv ]; then
    load_env
fi

set menu_color_normal=cyan/blue
set menu_color_highlight=white/blue

menuentry "LFS Linux" {
    linux /boot/vmlinuz-lfs root=/dev/sda3 ro quiet splash
    initrd /boot/initramfs.img
}

menuentry "LFS Linux (fallback)" {
    linux /boot/vmlinuz-lfs root=/dev/sda3 ro nomodeset
    initrd /boot/initramfs.img
}

menuentry "Memory Test" {
    linux16 /boot/memtest86+.bin
}

menuentry "System Rescue" {
    linux /boot/vmlinuz-lfs root=/dev/sda3 ro single
    initrd /boot/initramfs.img
}
GRUBCFG

# Install GRUB to disk (done in installer)
echo "Bootloader configuration ready"
EOF

chmod +x $LFS/configure-bootloader.sh

chroot "$LFS" /usr/bin/env -i \
    HOME=/root \
    TERM="$TERM" \
    PS1='(lfs chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin \
    /bin/bash /configure-bootloader.sh

log_info "Bootloader configuration complete!"