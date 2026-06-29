#!/bin/bash
# Configure LFS system - Compatible with Docker and native Linux
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/../common/utils.sh" ]; then
    source "$SCRIPT_DIR/../common/utils.sh"
else
    log_info() { echo "[INFO] $*"; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_warning() { echo "[WARNING] $*"; }
    log_success() { echo "[SUCCESS] $*"; }
fi

IN_DOCKER=false
if [ -f /.dockerenv ] || [ -f /run/.containerenv ] || grep -q docker /proc/1/cgroup 2>/dev/null; then
    IN_DOCKER=true
    log_info "Running in Docker container"
fi

if [ "$IN_DOCKER" = true ]; then
    LFS=${LFS:-/output/image}
else
    LFS=${LFS:-/mnt/lfs}
fi

if [ -z "$LFS" ]; then
    log_error "LFS variable not set"
    exit 1
fi

run_privileged() {
    if [ "$(whoami)" = "root" ]; then
        "$@"
    else
        sudo "$@"
    fi
}

log_info "========================================="
log_info "Configuring LFS system"
log_info "========================================="

if [ "$IN_DOCKER" = true ]; then
    log_info "Docker mode – minimal config inside $LFS"
    run_privileged mkdir -pv "$LFS"/etc/X11/xorg.conf.d
    run_privileged mkdir -pv "$LFS"/usr/local/bin

    cat > "$LFS/configure-system.sh" << 'INNEREOF'
#!/bin/bash
set -e
echo "Configuring LFS system (Docker mode)..."
if ! chroot . id lfsuser &>/dev/null; then
    chroot . groupadd -g 1000 lfsuser 2>/dev/null || true
    chroot . useradd -u 1000 -g 1000 -G wheel,audio,video,storage -m lfsuser 2>/dev/null || true
    chroot . sh -c 'echo "lfsuser:password123" | chpasswd' 2>/dev/null || true
fi
echo "lfsuser ALL=(ALL) ALL" >> ./etc/sudoers 2>/dev/null || true
cat > ./etc/X11/xorg.conf.d/00-keyboard.conf << "XORG"
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "us"
EndSection
XORG
cat > ./usr/local/bin/start-desktop << "START"
#!/bin/bash
exec startx
START
chmod +x ./usr/local/bin/start-desktop
echo "lfs-desktop" > ./etc/hostname
cat > ./etc/hosts << "HOSTS"
127.0.0.1   localhost.localdomain localhost
::1         localhost ip6-localhost ip6-loopback
127.0.1.1   lfs-desktop
HOSTS
echo "System configuration complete (Docker mode)!"
INNEREOF
    run_privileged chmod +x "$LFS/configure-system.sh"
    cd "$LFS" && run_privileged ./configure-system.sh
    log_success "LFS configuration complete (Docker mode)"
    exit 0
fi

# Native mode
log_info "Native mode – full configuration"

run_privileged mkdir -p "$LFS"/etc/X11/xorg.conf.d
run_privileged mkdir -p "$LFS"/usr/local/bin

cat > "$LFS/configure-system.sh" << 'INNEREOF'
#!/bin/bash
set -e
echo "========================================="
echo "Configuring LFS System"
echo "========================================="

# Create initramfs if mkinitcpio exists
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
if ! id lfsuser &>/dev/null; then
    groupadd -g 1000 lfsuser 2>/dev/null || true
    useradd -u 1000 -g 1000 -G wheel,audio,video,storage -m lfsuser 2>/dev/null || true
    echo "lfsuser:password123" | chpasswd 2>/dev/null || true
fi

# Setup sudo
echo "lfsuser ALL=(ALL) ALL" >> /etc/sudoers 2>/dev/null || true

# Keyboard config
mkdir -pv /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/00-keyboard.conf << "XORG"
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "us"
EndSection
XORG

# Desktop starter
cat > /usr/local/bin/start-desktop << "START"
#!/bin/bash
exec startx
START
chmod +x /usr/local/bin/start-desktop

# Network config
echo "lfs-desktop" > /etc/hostname
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

run_privileged chmod +x "$LFS/configure-system.sh"

# Monter les systèmes de fichiers virtuels
run_privileged mount --bind /dev $LFS/dev 2>/dev/null || true
run_privileged mount -t devpts devpts $LFS/dev/pts 2>/dev/null || true
run_privileged mount -t proc proc $LFS/proc 2>/dev/null || true
run_privileged mount -t sysfs sysfs $LFS/sys 2>/dev/null || true
run_privileged mount -t tmpfs tmpfs $LFS/run 2>/dev/null || true

# Exécuter la configuration dans le chroot
log_info "Running configuration in chroot..."
run_privileged chroot "$LFS" /bin/bash /configure-system.sh

# Démontage
run_privileged umount $LFS/dev/pts 2>/dev/null || true
run_privileged umount $LFS/dev 2>/dev/null || true
run_privileged umount $LFS/proc 2>/dev/null || true
run_privileged umount $LFS/sys 2>/dev/null || true
run_privileged umount $LFS/run 2>/dev/null || true

log_success "LFS configuration complete!"