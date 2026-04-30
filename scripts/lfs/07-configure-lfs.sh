#!/bin/bash
# Configure LFS system

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/utils.sh"

log_info "Configuring LFS system"

cat > $LFS/configure-system.sh << "EOF"
#!/bin/bash

set -e

# Create initramfs
echo "Creating initramfs..."
mkinitcpio -p linux

# Setup bootloader
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=LFS --recheck
grub-mkconfig -o /boot/grub/grub.cfg

# Enable services
systemctl enable systemd-networkd
systemctl enable systemd-resolved
systemctl enable systemd-timesyncd
systemctl enable sshd
systemctl enable dbus

# Create user
groupadd -g 1000 lfsuser
useradd -u 1000 -g 1000 -G wheel,audio,video,storage -m lfsuser
echo "lfsuser:password123" | chpasswd

# Setup sudo
echo "lfsuser ALL=(ALL) ALL" >> /etc/sudoers

# Create basic Xorg configuration
cat > /etc/X11/xorg.conf.d/00-keyboard.conf << "XORG"
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "us"
EndSection
XORG

# Setup desktop environment script
cat > /usr/local/bin/start-desktop << "START"
#!/bin/bash
exec startx
START

chmod +x /usr/local/bin/start-desktop

echo "System configuration complete!"
EOF

chmod +x $LFS/configure-system.sh

chroot "$LFS" /usr/bin/env -i \
    HOME=/root \
    TERM="$TERM" \
    PS1='(lfs chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin \
    /bin/bash /configure-system.sh

log_info "LFS configuration complete!"