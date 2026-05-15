#!/bin/bash
# Build complete LFS system with init system choice
# Orchestrates all 6 init-related scripts

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/utils.sh"

log_info "========================================="
log_info "Building LFS System with Init System Choice"
log_info "========================================="

# Vérifier LFS
if [ -z "$LFS" ]; then
    log_error "LFS variable not set"
    exit 1
fi

# Charger la configuration de l'init system
if [ -f "$SCRIPT_DIR/../config/init.conf" ]; then
    source "$SCRIPT_DIR/../config/init.conf"
else
    log_warning "config/init.conf not found, using defaults"
    INIT_SYSTEM="${INIT_SYSTEM:-sysvinit}"
    SYSVINIT_STYLE="${SYSVINIT_STYLE:-lfs-classic}"
fi

log_info "Init system selected: $INIT_SYSTEM"

# Monter les systèmes de fichiers virtuels
log_info "Mounting virtual filesystems"
mount -v --bind /dev $LFS/dev 2>/dev/null || true
mount -vt devpts devpts $LFS/dev/pts 2>/dev/null || true
mount -vt proc proc $LFS/proc 2>/dev/null || true
mount -vt sysfs sysfs $LFS/sys 2>/dev/null || true
mount -vt tmpfs tmpfs $LFS/run 2>/dev/null || true

# Copier les scripts d'init dans le chroot
log_info "Copying init scripts to chroot"
for script in 06a-init-system.sh 06b-service-management.sh 06c-boot-scripts.sh 06d-systemd-config.sh 06e-init-selector.sh; do
    if [ -f "$SCRIPT_DIR/$script" ]; then
        cp "$SCRIPT_DIR/$script" "$LFS/init-$script"
        chmod +x "$LFS/init-$script"
    fi
done

# Créer le script de build principal dans le chroot
cat > "$LFS/build-system.sh" << 'EOF'
#!/bin/bash
set -e

# Colors
log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[0;34m[SUCCESS]\033[0m $1"; }
log_warning() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }

# Variables d'environnement
export INIT_SYSTEM="$INIT_SYSTEM"
export SYSVINIT_STYLE="$SYSVINIT_STYLE"

cd /sources

# ============================================================================
# 1. Kernel Linux
# ============================================================================
if [ ! -f /boot/vmlinuz-lfs ]; then
    log_info "Building Linux Kernel 6.12.20..."
    tar -xf linux-6.12.20.tar.xz
    cd linux-6.12.20
    make mrproper
    make defconfig
    make -j$(nproc)
    make modules_install
    cp -v arch/x86/boot/bzImage /boot/vmlinuz-lfs
    cp -v System.map /boot/System.map
    cp -v .config /boot/config
    cd ..
else
    log_warning "Kernel already built, skipping"
fi

# ============================================================================
# 2. Init System - Call the appropriate installer
# ============================================================================
log_info "Installing init system: $INIT_SYSTEM"

if [ -f "/init-06a-init-system.sh" ]; then
    /bin/bash /init-06a-init-system.sh
else
    log_warning "Init system script not found"
fi

# ============================================================================
# 3. Service Management Abstraction
# ============================================================================
if [ -f "/init-06b-service-management.sh" ]; then
    /bin/bash /init-06b-service-management.sh
fi

# ============================================================================
# 4. Boot Scripts (for sysvinit) or Systemd Config
# ============================================================================
if [ "$INIT_SYSTEM" = "sysvinit" ] && [ -f "/init-06c-boot-scripts.sh" ]; then
    /bin/bash /init-06c-boot-scripts.sh
elif [ "$INIT_SYSTEM" = "systemd" ] && [ -f "/init-06d-systemd-config.sh" ]; then
    /bin/bash /init-06d-systemd-config.sh
fi

# ============================================================================
# 5. GRUB Bootloader
# ============================================================================
if [ ! -f /usr/bin/grub-install ]; then
    log_info "Building GRUB 2.14..."
    tar -xf grub-2.14.tar.xz
    cd grub-2.14
    ./configure --prefix=/usr --sysconfdir=/etc --disable-efiemu
    make -j$(nproc)
    make install
    cd ..
fi

# ============================================================================
# 6. D-Bus (message bus system)
# ============================================================================
if [ ! -f /usr/bin/dbus-daemon ]; then
    log_info "Building D-Bus 1.16.2..."
    tar -xf dbus-1.16.2.tar.xz
    cd dbus-1.16.2
    ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --runstatedir=/run
    make -j$(nproc)
    make install
    cd ..
fi

# ============================================================================
# 7. OpenSSL
# ============================================================================
if [ ! -f /usr/bin/openssl ]; then
    log_info "Building OpenSSL 3.6.1..."
    tar -xf openssl-3.6.1.tar.gz
    cd openssl-3.6.1
    ./config --prefix=/usr --openssldir=/etc/ssl --libdir=lib shared zlib-dynamic
    make -j$(nproc)
    make install
    cd ..
fi

# ============================================================================
# 8. OpenSSH
# ============================================================================
if [ ! -f /usr/sbin/sshd ]; then
    log_info "Building OpenSSH 9.9p2..."
    tar -xf openssh-9.9p2.tar.gz
    cd openssh-9.9p2
    ./configure --prefix=/usr --sysconfdir=/etc/ssh --with-md5-passwords --with-privsep-path=/var/lib/sshd
    make -j$(nproc)
    make install
    install -v -m755 contrib/ssh-copy-id /usr/bin 2>/dev/null || true
    ssh-keygen -A
    cd ..
fi

# ============================================================================
# 9. System Configuration
# ============================================================================
log_info "Configuring system"

# fstab
cat > /etc/fstab << "FSTAB"
# /etc/fstab
/dev/sda3      /            ext4    defaults            1     1
/dev/sda1      /boot        vfat    defaults            0     2
/dev/sda2      swap         swap    pri=1               0     0
proc           /proc        proc    nosuid,noexec,nodev 0     0
sysfs          /sys         sysfs   nosuid,noexec,nodev 0     0
devpts         /dev/pts     devpts  gid=5,mode=620      0     0
tmpfs          /run         tmpfs   defaults            0     0
devtmpfs       /dev         devtmpfs mode=0755,nosuid   0     0
tmpfs          /dev/shm     tmpfs   nosuid,nodev        0     0
FSTAB

# Hostname
echo "lfs-desktop" > /etc/hostname

# Hosts
cat > /etc/hosts << "HOSTS"
127.0.0.1   localhost.localdomain localhost
::1         localhost ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
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

log_success "LFS system build complete!"
EOF

chmod +x "$LFS/build-system.sh"

# Exécuter dans le chroot
log_info "Running system build in chroot"
chroot "$LFS" /usr/bin/env -i \
    HOME=/root \
    TERM="$TERM" \
    PS1='(lfs chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin:/bin \
    INIT_SYSTEM="$INIT_SYSTEM" \
    SYSVINIT_STYLE="$SYSVINIT_STYLE" \
    /bin/bash /build-system.sh

# Nettoyer
log_info "Cleaning up"
rm -f "$LFS"/init-*.sh "$LFS"/build-system.sh

umount -v $LFS/dev/pts 2>/dev/null || true
umount -v $LFS/dev 2>/dev/null || true
umount -v $LFS/proc 2>/dev/null || true
umount -v $LFS/sys 2>/dev/null || true
umount -v $LFS/run 2>/dev/null || true

log_success "LFS system build complete!"