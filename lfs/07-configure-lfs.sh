#!/bin/bash
# Configure LFS system - Compatible with Docker and native Linux

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fallback functions if utils.sh doesn't exist
if [ -f "$SCRIPT_DIR/../common/utils.sh" ]; then
    source "$SCRIPT_DIR/../common/utils.sh"
else
    log_info() { echo "[INFO] $*"; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_warning() { echo "[WARNING] $*"; }
    log_success() { echo "[SUCCESS] $*"; }
fi

# Detect if running in Docker
IN_DOCKER=false
if [ -f /.dockerenv ] || [ -f /run/.containerenv ] || grep -q docker /proc/1/cgroup 2>/dev/null; then
    IN_DOCKER=true
    log_info "Running in Docker container"
fi

# Set LFS directory
if [ "$IN_DOCKER" = true ]; then
    LFS=${LFS:-/output/image}
else
    LFS=${LFS:-/mnt/lfs}
fi

if [ -z "$LFS" ]; then
    log_error "LFS variable not set"
    exit 1
fi

log_info "========================================="
log_info "Configuring LFS system"
log_info "========================================="

# If in Docker, create minimal configuration inside $LFS
if [ "$IN_DOCKER" = true ]; then
    log_info "Running in Docker mode - creating minimal configuration inside $LFS"
    
    # Create directories inside LFS
    mkdir -pv $LFS/etc/X11/xorg.conf.d
    mkdir -pv $LFS/usr/local/bin
    
    # Create configure script that operates inside $LFS
    cat > $LFS/configure-system.sh << 'INNEREOF'
#!/bin/bash
set -e

echo "Configuring LFS system (Docker mode)..."

# Create user inside LFS
if ! chroot $LFS id lfsuser &>/dev/null; then
    chroot $LFS groupadd -g 1000 lfsuser 2>/dev/null || true
    chroot $LFS useradd -u 1000 -g 1000 -G wheel,audio,video,storage -m lfsuser 2>/dev/null || true
    chroot $LFS sh -c 'echo "lfsuser:password123" | chpasswd' 2>/dev/null || true
fi

# Setup sudo inside LFS
echo "lfsuser ALL=(ALL) ALL" >> $LFS/etc/sudoers 2>/dev/null || true

# Keyboard configuration inside LFS
cat > $LFS/etc/X11/xorg.conf.d/00-keyboard.conf << "XORG"
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "us"
EndSection
XORG

# Start desktop script inside LFS
cat > $LFS/usr/local/bin/start-desktop << "START"
#!/bin/bash
echo "Starting desktop (Docker mode)..."
exec startx
START
chmod +x $LFS/usr/local/bin/start-desktop

# Hostname inside LFS
cat > $LFS/etc/hostname << "HOSTNAME"
lfs-desktop
HOSTNAME

# Hosts inside LFS
cat > $LFS/etc/hosts << "HOSTS"
127.0.0.1   localhost.localdomain localhost
::1         localhost ip6-localhost ip6-loopback
127.0.1.1   lfs-desktop
HOSTS

echo "System configuration complete (Docker mode)!"
INNEREOF

    chmod +x $LFS/configure-system.sh
    
    # Run the configuration script inside the LFS environment
    log_info "Running configuration inside LFS"
    cd $LFS && ./configure-system.sh
    
    log_success "LFS configuration complete (Docker mode)"
    exit 0
fi

# Native mode - full configuration
log_info "Running in native mode - full configuration"

# Create configure script for chroot
cat > $LFS/configure-system.sh << 'INNEREOF'
#!/bin/bash
set -e

echo "========================================="
echo "Configuring LFS System"
echo "========================================="

# Create initramfs
if command -v mkinitcpio &> /dev/null; then
    echo "Creating initramfs..."
    mkinitcpio -p linux 2>/dev/null || true
fi

# Setup bootloader
if command -v grub-install &> /dev/null; then
    echo "Setting up GRUB bootloader..."
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=LFS --recheck 2>/dev/null || true
    grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || true
fi

# Enable services based on init system
if command -v systemctl &> /dev/null; then
    echo "Enabling systemd services..."
    systemctl enable systemd-networkd 2>/dev/null || true
    systemctl enable systemd-resolved 2>/dev/null || true
    systemctl enable systemd-timesyncd 2>/dev/null || true
    systemctl enable sshd 2>/dev/null || true
    systemctl enable dbus 2>/dev/null || true
fi

# Create user
echo "Creating user..."
if ! id lfsuser &>/dev/null; then
    groupadd -g 1000 lfsuser 2>/dev/null || true
    useradd -u 1000 -g 1000 -G wheel,audio,video,storage -m lfsuser 2>/dev/null || true
    echo "lfsuser:password123" | chpasswd 2>/dev/null || true
else
    echo "User lfsuser already exists"
fi

# Setup sudo
echo "Configuring sudo..."
echo "lfsuser ALL=(ALL) ALL" >> /etc/sudoers 2>/dev/null || true

# Create Xorg configuration
echo "Configuring Xorg..."
mkdir -pv /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/00-keyboard.conf << "XORG"
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "us"
EndSection
XORG

# Create start-desktop script
cat > /usr/local/bin/start-desktop << "START"
#!/bin/bash
exec startx
START
chmod +x /usr/local/bin/start-desktop

# Basic network configuration
cat > /etc/hostname << "HOSTNAME"
lfs-desktop
HOSTNAME

cat > /etc/hosts << "HOSTS"
127.0.0.1   localhost.localdomain localhost
::1         localhost ip6-localhost ip6-loopback
127.0.1.1   lfs-desktop
HOSTS

# Timezone
ln -sfv /usr/share/zoneinfo/UTC /etc/localtime

# Locale
cat > /etc/locale.conf << "LOCALE"
LANG=en_US.UTF-8
LOCALE

# Console
cat > /etc/vconsole.conf << "VCONSOLE"
KEYMAP=us
FONT=Lat2-Terminus16
VCONSOLE

echo "========================================="
echo "System configuration complete!"
echo "========================================="
INNEREOF

chmod +x $LFS/configure-system.sh

# Mount virtual filesystems if needed
log_info "Mounting virtual filesystems"
mount -v --bind /dev $LFS/dev 2>/dev/null || true
mount -vt devpts devpts $LFS/dev/pts 2>/dev/null || true
mount -vt proc proc $LFS/proc 2>/dev/null || true
mount -vt sysfs sysfs $LFS/sys 2>/dev/null || true
mount -vt tmpfs tmpfs $LFS/run 2>/dev/null || true

# Run configuration in chroot
log_info "Running configuration in chroot"
chroot "$LFS" /usr/bin/env -i \
    HOME=/root \
    TERM="$TERM" \
    PS1='(lfs chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin:/bin \
    /bin/bash /configure-system.sh

# Unmount virtual filesystems
log_info "Unmounting virtual filesystems"
umount -v $LFS/dev/pts 2>/dev/null || true
umount -v $LFS/dev 2>/dev/null || true
umount -v $LFS/proc 2>/dev/null || true
umount -v $LFS/sys 2>/dev/null || true
umount -v $LFS/run 2>/dev/null || true

log_success "LFS configuration complete!"
