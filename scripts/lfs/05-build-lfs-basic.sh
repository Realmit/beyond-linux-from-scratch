#!/bin/bash
# Build basic LFS system (run as lfs user after chroot)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/utils.sh"

log_info "Building basic LFS system"

# Enter chroot if not already
if [ ! -f "$LFS/usr/bin/bash" ]; then
    log_error "Chroot environment not ready"
    exit 1
fi

# Create chroot script
cat > $LFS/build-basic.sh << "EOF"
#!/bin/bash

set -e

# Create directory structure
mkdir -pv /{boot,home,mnt,opt,srv}
mkdir -pv /etc/{opt,sysconfig}
mkdir -pv /lib/firmware
mkdir -pv /media/{floppy,cdrom}
mkdir -pv /usr/{local,share}
mkdir -pv /usr/local/{bin,include,lib,sbin,src}
mkdir -pv /usr/local/etc
mkdir -pv /var/{cache,lib,local,log,opt,spool}
mkdir -pv /var/lib/{color,misc,locate}
ln -sfv /run /var/run
ln -sfv /run/lock /var/lock
install -dv -m 0750 /root
install -dv -m 1777 /tmp /var/tmp

# Create essential symlinks
ln -sv /proc/self/mounts /etc/mtab
ln -sv /proc/self/fd /dev/fd
ln -sv /proc/self/fd/0 /dev/stdin
ln -sv /proc/self/fd/1 /dev/stdout
ln -sv /proc/self/fd/2 /dev/stderr

# Setup users and groups
cat > /etc/passwd << "PASSWD"
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/usr/bin/false
daemon:x:6:6:daemon:/dev/null:/usr/bin/false
messagebus:x:18:18:D-Bus Message Daemon User:/run/dbus:/usr/bin/false
systemd-journal-gateway:x:73:73:systemd Journal Gateway:/:/usr/bin/false
systemd-journal-remote:x:74:74:systemd Journal Remote:/:/usr/bin/false
systemd-journal-upload:x:75:75:systemd Journal Upload:/:/usr/bin/false
systemd-network:x:76:76:systemd Network Management:/:/usr/bin/false
systemd-resolve:x:77:77:systemd Resolver:/:/usr/bin/false
systemd-timesync:x:78:78:systemd Time Synchronization:/:/usr/bin/false
nobody:x:65534:65534:Unprivileged User:/dev/null:/usr/bin/false
PASSWD

cat > /etc/group << "GROUP"
root:x:0:
bin:x:1:daemon
sys:x:2:
kmem:x:3:
tape:x:4:
tty:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
usb:x:14:
cdrom:x:15:
adm:x:16:
messagebus:x:18:
systemd-journal:x:23:
input:x:24:
systemd-network:x:76:
dbus:x:81:
systemd-journal-gateway:x:73:
systemd-journal-remote:x:74:
systemd-journal-upload:x:75:
systemd-resolve:x:77:
systemd-timesync:x:78:
wheel:x:97:
users:x:999:
nogroup:x:65534:
GROUP

# Setup password
echo "root:root123" | chpasswd

# Create shell profile
cat > /etc/profile << "PROFILE"
export LANG=en_US.UTF-8
export INPUTRC=/etc/inputrc
export PATH=/usr/local/bin:/usr/bin:/bin
PROFILE

# Create inputrc
cat > /etc/inputrc << "INPUTRC"
set horizontal-scroll-mode Off
set meta-flag On
set input-meta On
set convert-meta Off
set output-meta On
set bell-style none
"\eOd": backward-word
"\eOc": forward-word
"\e[1~": beginning-of-line
"\e[4~": end-of-line
"\e[5~": beginning-of-history
"\e[6~": end-of-history
"\e[3~": delete-char
"\e[2~": quoted-insert
"\eOH": beginning-of-line
"\eOF": end-of-line
"\e[H": beginning-of-line
"\e[F": end-of-line
INPUTRC

# Build gettext
cd /sources
tar -xf gettext-*.tar.xz
cd gettext-*
./configure --prefix=/usr --disable-shared
make -j$(nproc)
make install
cp -v gettext-tools/src/{msgfmt,msgmerge,xgettext} /usr/bin
cd ..

# Build Bison
tar -xf bison-*.tar.xz
cd bison-*
./configure --prefix=/usr
make -j$(nproc)
make install
cd ..

# Build Perl
tar -xf perl-*.tar.xz
cd perl-*
sh Configure -des -Dprefix=/usr -Dvendorprefix=/usr -Duseshrplib
make -j$(nproc)
make install
cd ..

# Build Python
tar -xf Python-*.tar.xz
cd Python-*
./configure --prefix=/usr --enable-shared --with-system-expat --with-system-ffi --enable-optimizations
make -j$(nproc)
make install
cd ..

# Build Texinfo
tar -xf texinfo-*.tar.xz
cd texinfo-*
./configure --prefix=/usr
make -j$(nproc)
make install
cd ..

# Build util-linux
tar -xf util-linux-*.tar.xz
cd util-linux-*
./configure --prefix=/usr --bindir=/usr/bin --libdir=/usr/lib --enable-libblkid --enable-libmount --enable-libfdisk --enable-libsmartcols
make -j$(nproc)
make install
cd ..

# Cleanup
find /usr/lib -type f -name '*.a' -delete
rm -rf /tmp/*

echo "Basic system build complete!"
EOF

chmod +x $LFS/build-basic.sh

# Run in chroot
log_info "Running basic system build in chroot"
chroot "$LFS" /usr/bin/env -i \
    HOME=/root \
    TERM="$TERM" \
    PS1='(lfs chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin \
    /bin/bash /build-basic.sh

log_info "Basic LFS system build complete!"