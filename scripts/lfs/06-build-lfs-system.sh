#!/bin/bash
# Build complete LFS system

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/utils.sh"

log_info "Building complete LFS system"

# Vérifier que LFS est défini
if [ -z "$LFS" ]; then
    log_error "LFS variable not set"
    exit 1
fi

# Monter les systèmes de fichiers virtuels si nécessaire
log_info "Mounting virtual filesystems"
mount -v --bind /dev $LFS/dev 2>/dev/null || true
mount -vt devpts devpts $LFS/dev/pts 2>/dev/null || true
mount -vt proc proc $LFS/proc 2>/dev/null || true
mount -vt sysfs sysfs $LFS/sys 2>/dev/null || true
mount -vt tmpfs tmpfs $LFS/run 2>/dev/null || true

# Créer le script de build système
cat > $LFS/build-system.sh << "EOF"
#!/bin/bash

set -e
cd /sources

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_warning() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }

# Linux Kernel
if [ ! -f /boot/vmlinuz-lfs ]; then
    log_info "Building Linux Kernel..."
    tar -xf linux-*.tar.xz
    cd linux-*
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

# Systemd (optionnel, si systemd est choisi)
if [ "$INIT_SYSTEM" = "systemd" ] && [ ! -f /usr/lib/systemd/systemd ]; then
    log_info "Building systemd..."
    tar -xf systemd-*.tar.gz
    cd systemd-*
    sed -i 's/GROUP="render"/GROUP="video"/' rules.d/50-udev-default.rules.in
    mkdir -p build
    cd build
    meson setup --prefix=/usr --buildtype=release \
        -Ddefault-dnssec=no \
        -Dfirstboot=false \
        -Dinstall-tests=false \
        -Dldconfig=false \
        -Dsysusers=false \
        -Drpmmacrosdir=no \
        -Dhomed=false \
        -Duserdb=false \
        -Dman=false \
        -Dmode=release \
        -Ddocdir=/usr/share/doc/systemd-255 ..
    meson compile
    meson install
    cd ../..
else
    log_warning "systemd already built or not selected, skipping"
fi

# GRUB
if [ ! -f /usr/bin/grub-install ]; then
    log_info "Building GRUB..."
    tar -xf grub-*.tar.xz
    cd grub-*
    ./configure --prefix=/usr --sysconfdir=/etc --disable-efiemu
    make -j$(nproc)
    make install
    mv -v /etc/bash_completion.d/grub /usr/share/bash-completion/completions 2>/dev/null || true
    cd ..
else
    log_warning "GRUB already built, skipping"
fi

# D-Bus
if [ ! -f /usr/bin/dbus-daemon ]; then
    log_info "Building D-Bus..."
    tar -xf dbus-*.tar.xz
    cd dbus-*
    ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --runstatedir=/run
    make -j$(nproc)
    make install
    cd ..
else
    log_warning "D-Bus already built, skipping"
fi

# OpenSSL
if [ ! -f /usr/bin/openssl ]; then
    log_info "Building OpenSSL..."
    tar -xf openssl-*.tar.gz
    cd openssl-*
    ./config --prefix=/usr --openssldir=/etc/ssl --libdir=lib shared zlib-dynamic
    make -j$(nproc)
    make install
    cd ..
else
    log_warning "OpenSSL already built, skipping"
fi

# OpenSSH
if [ ! -f /usr/sbin/sshd ]; then
    log_info "Building OpenSSH..."
    tar -xf openssh-*.tar.gz
    cd openssh-*
    ./configure --prefix=/usr --sysconfdir=/etc/ssh --with-md5-passwords --with-privsep-path=/var/lib/sshd
    make -j$(nproc)
    make install
    install -v -m755    contrib/ssh-copy-id /usr/bin 2>/dev/null || true
    install -v -m644    contrib/ssh-copy-id.1 /usr/share/man/man1 2>/dev/null || true
    install -v -m755 -d /usr/share/doc/openssh-9.6p1 2>/dev/null || true
    ssh-keygen -A
    cd ..
else
    log_warning "OpenSSH already built, skipping"
fi

# Créer fstab
cat > /etc/fstab << "FSTAB"
# Begin /etc/fstab

/dev/sda3      /            ext4    defaults            1     1
/dev/sda1      /boot        vfat    defaults            0     2
/dev/sda2      swap         swap    pri=1               0     0
proc           /proc        proc    nosuid,noexec,nodev 0     0
sysfs          /sys         sysfs   nosuid,noexec,nodev 0     0
devpts         /dev/pts     devpts  gid=5,mode=620      0     0
tmpfs          /run         tmpfs   defaults            0     0
devtmpfs       /dev         devtmpfs mode=0755,nosuid   0     0
tmpfs          /dev/shm     tmpfs   nosuid,nodev        0     0
cgroup2        /sys/fs/cgroup cgroup2 nosuid,noexec,nodev 0   0

# End /etc/fstab
FSTAB

# Configure network
echo "lfs-desktop" > /etc/hostname

cat > /etc/hosts << "HOSTS"
127.0.0.1 localhost.localdomain localhost
::1       localhost ip6-localhost ip6-loopback
ff02::1   ip6-allnodes
ff02::2   ip6-allrouters
127.0.1.1 lfs-desktop
HOSTS

# Configure systemd network
if [ -d /etc/systemd/network ]; then
    mkdir -p /etc/systemd/network
    cat > /etc/systemd/network/20-dhcp.network << "NETWORK"
[Match]
Name=en*
Name=eth*

[Network]
DHCP=yes
NETWORK
fi

# Configure timezone
ln -sfv /usr/share/zoneinfo/America/New_York /etc/localtime

# Configure locale
cat > /etc/locale.conf << "LOCALE"
LANG=en_US.UTF-8
LOCALE

# Configure console
cat > /etc/vconsole.conf << "VCONSOLE"
KEYMAP=us
FONT=Lat2-Terminus16
VCONSOLE

log_info "LFS system build complete!"
EOF

chmod +x $LFS/build-system.sh

# Trouver le bon chemin pour bash
BASH_PATH=""
if [ -x "$LFS/bin/bash" ]; then
    BASH_PATH="/bin/bash"
elif [ -x "$LFS/usr/bin/bash" ]; then
    BASH_PATH="/usr/bin/bash"
else
    log_error "bash not found in chroot"
    exit 1
fi

# Exécuter dans le chroot
log_info "Running system build in chroot"
chroot "$LFS" /usr/bin/env -i \
    HOME=/root \
    TERM="$TERM" \
    PS1='(lfs chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin:/bin \
    INIT_SYSTEM="$INIT_SYSTEM" \
    /bin/bash /build-system.sh

# Nettoyer les mounts
log_info "Cleaning up mounts"
umount -v $LFS/dev/pts 2>/dev/null || true
umount -v $LFS/dev 2>/dev/null || true
umount -v $LFS/proc 2>/dev/null || true
umount -v $LFS/sys 2>/dev/null || true
umount -v $LFS/run 2>/dev/null || true

log_info "LFS system build complete!"