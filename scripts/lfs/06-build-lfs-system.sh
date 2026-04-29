#!/bin/bash
# Build complete LFS system

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/utils.sh"

log_info "Building complete LFS system"

cat > $LFS/build-system.sh << "EOF"
#!/bin/bash

set -e
cd /sources

# Linux Kernel
echo "Building Linux Kernel..."
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

# Systemd
echo "Building systemd..."
tar -xf systemd-*.tar.gz
cd systemd-*
sed -i 's/GROUP="render"/GROUP="video"/' rules.d/50-udev-default.rules.in
mkdir -p build
cd build
meson setup --prefix=/usr --buildtype=release -Ddefault-dnssec=no -Dfirstboot=false -Dinstall-tests=false -Dldconfig=false -Dsysusers=false -Drpmmacrosdir=no -Dhomed=false -Duserdb=false -Dman=false -Dmode=release -Ddocdir=/usr/share/doc/systemd-255 ..
meson compile
meson install
cd ../..

# GRUB
echo "Building GRUB..."
tar -xf grub-*.tar.xz
cd grub-*
./configure --prefix=/usr --sysconfdir=/etc --disable-efiemu
make -j$(nproc)
make install
mv -v /etc/bash_completion.d/grub /usr/share/bash-completion/completions
cd ..

# D-Bus
echo "Building D-Bus..."
tar -xf dbus-*.tar.xz
cd dbus-*
./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --runstatedir=/run
make -j$(nproc)
make install
cd ..

# OpenSSL
echo "Building OpenSSL..."
tar -xf openssl-*.tar.gz
cd openssl-*
./config --prefix=/usr --openssldir=/etc/ssl --libdir=lib shared zlib-dynamic
make -j$(nproc)
make install
cd ..

# OpenSSH
echo "Building OpenSSH..."
tar -xf openssh-*.tar.gz
cd openssh-*
./configure --prefix=/usr --sysconfdir=/etc/ssh --with-md5-passwords --with-privsep-path=/var/lib/sshd
make -j$(nproc)
make install
install -v -m755    contrib/ssh-copy-id /usr/bin
install -v -m644    contrib/ssh-copy-id.1 /usr/share/man/man1
install -v -m755 -d /usr/share/doc/openssh-9.6p1
install -v -m644    INSTALL LICENCE OVERVIEW README* /usr/share/doc/openssh-9.6p1
ssh-keygen -A
cd ..

# Create fstab
cat > /etc/fstab << "FSTAB"
# Begin /etc/fstab

# file system  mount-point  type     options             dump  fsck
#                                                              order

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
cat > /etc/hostname << "HOSTNAME"
lfs-desktop
HOSTNAME

cat > /etc/hosts << "HOSTS"
127.0.0.1 localhost.localdomain localhost
::1       localhost ip6-localhost ip6-loopback
ff02::1   ip6-allnodes
ff02::2   ip6-allrouters
127.0.1.1 lfs-desktop
HOSTS

# Configure systemd network
mkdir -p /etc/systemd/network
cat > /etc/systemd/network/20-dhcp.network << "NETWORK"
[Match]
Name=en*

[Network]
DHCP=yes
NETWORK

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

echo "LFS system build complete!"
EOF

chmod +x $LFS/build-system.sh

chroot "$LFS" /usr/bin/env -i \
    HOME=/root \
    TERM="$TERM" \
    PS1='(lfs chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin \
    /bin/bash /build-system.sh

log_info "LFS system build complete!"