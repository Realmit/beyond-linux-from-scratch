#!/bin/bash
# Prepare host system for LFS build

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/utils.sh"
source "$SCRIPT_DIR/../common/error-handler.sh"

setup_error_handling

log_info "Preparing host system for LFS build"

# Create LFS user if not exists
if ! id "lfs" &>/dev/null; then
    log_info "Creating lfs user"
    groupadd lfs
    useradd -s /bin/bash -g lfs -m -k /dev/null lfs
    echo "lfs:lfs123" | chpasswd
    echo "lfs ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
fi

# Create LFS directory structure
LFS=${LFS:-/mnt/lfs}
mkdir -pv $LFS
chown -v lfs:lfs $LFS

# Create necessary directories
mkdir -pv $LFS/{bin,boot,dev,etc,home,lib,lib64,media,mnt,opt,proc,root,run,sbin,srv,sys,tmp,usr,var}
mkdir -pv $LFS/usr/{bin,include,lib,lib64,sbin,share,src}
mkdir -pv $LFS/usr/share/{man,doc,info}
mkdir -pv $LFS/var/{cache,lib,local,lock,log,opt,run,spool,tmp}
mkdir -pv $LFS/etc/{profile.d,sysconfig,skel}

# Set permissions
chmod -v 1777 $LFS/tmp
chmod -v 1777 $LFS/var/tmp

# Create sources directory
mkdir -pv $LFS/sources
chmod -v a+wt $LFS/sources
chown -v lfs:lfs $LFS/sources

# Create tools directory
mkdir -pv $LFS/tools
chown -v lfs:lfs $LFS/tools

# Set up lfs user environment
cat > /home/lfs/.bashrc << "EOF"
set +h
umask 022
LFS=/mnt/lfs
LC_ALL=POSIX
LFS_TGT=$(uname -m)-lfs-linux-gnu
PATH=/usr/bin
if [ ! -L /bin ]; then PATH=/bin:$PATH; fi
PATH=$LFS/tools/bin:$PATH
CONFIG_SITE=$LFS/usr/share/config.site
export LFS LC_ALL LFS_TGT PATH CONFIG_SITE
MAKEFLAGS="-j$(nproc)"
export MAKEFLAGS
EOF

cat > /home/lfs/.bash_profile << "EOF"
if [ -f "$HOME/.bashrc" ] ; then
    source "$HOME/.bashrc"
fi
EOF

chown lfs:lfs /home/lfs/.bashrc /home/lfs/.bash_profile

# Install build dependencies based on distribution
if command -v apt-get &> /dev/null; then
    log_info "Installing dependencies for Debian/Ubuntu"
    DEBIAN_FRONTEND=noninteractive apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        build-essential bison flex gawk texinfo \
        wget curl git python3 python3-pip \
        xorriso isolinux mtools dosfstools \
        parted rsync sudo \
        bc cpio unzip xz-utils \
        libssl-dev libelf-dev \
        kmod cpio

elif command -v yum &> /dev/null; then
    log_info "Installing dependencies for RHEL/CentOS/Fedora"
    yum groupinstall -y "Development Tools"
    yum install -y bison flex gawk texinfo wget curl git \
        python3 xorriso isolinux mtools dosfstools \
        parted rsync bc cpio xz unzip \
        openssl-devel elfutils-libelf-devel kmod
elif command -v pacman &> /dev/null; then
    log_info "Installing dependencies for Arch"
    pacman -S --noconfirm base-devel bison flex gawk texinfo \
        wget curl git python xorriso libisoburn mtools \
        dosfstools parted rsync bc cpio
fi

# Create build script
cat > $LFS/build-lfs.sh << "EOF"
#!/bin/bash
# Main LFS build script to be run as lfs user

cd /mnt/lfs/sources

# Download packages
wget --input-file=wget-list --continue --directory-prefix=/mnt/lfs/sources

# Verify packages
md5sum -c md5sums

# Build toolchain
echo "Building cross-toolchain..."
tar -xf binutils-*.tar.xz
cd binutils-*
mkdir -v build
cd build
../configure --prefix=$LFS/tools \
             --with-sysroot=$LFS \
             --target=$LFS_TGT \
             --disable-nls \
             --enable-gprofng=no \
             --disable-werror
make
make install
cd ../..

# GCC
tar -xf gcc-*.tar.xz
cd gcc-*
case $(uname -m) in
  x86_64)
    sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
  ;;
esac
mkdir -v build
cd build
../configure --target=$LFS_TGT \
             --prefix=$LFS/tools \
             --with-glibc-version=2.38 \
             --with-sysroot=$LFS \
             --with-newlib \
             --without-headers \
             --enable-default-pie \
             --enable-default-ssp \
             --disable-nls \
             --disable-shared \
             --disable-multilib \
             --disable-threads \
             --disable-libatomic \
             --disable-libgomp \
             --disable-libquadmath \
             --disable-libssp \
             --disable-libvtv \
             --disable-libstdcxx \
             --enable-languages=c,c++
make
make install
cd ../..

# Linux API Headers
tar -xf linux-*.tar.xz
cd linux-*
make mrproper
make headers
find usr/include -type f ! -name '*.h' -delete
cp -rv usr/include $LFS/usr
cd ..

# Glibc
tar -xf glibc-*.tar.xz
cd glibc-*
case $(uname -m) in
    i?86)   ln -sfv ld-linux.so.2 $LFS/lib/ld-lsb.so.3
    ;;
    x86_64) ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64
            ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64/ld-lsb-x86-64.so.3
    ;;
esac
patch -Np1 -i ../glibc-2.38-fhs-1.patch
mkdir -v build
cd build
echo "rootsbindir=/usr/sbin" > configparms
../configure --prefix=/usr \
             --host=$LFS_TGT \
             --build=$(../scripts/config.guess) \
             --enable-kernel=4.14 \
             --with-headers=$LFS/usr/include \
             libc_cv_slibdir=/usr/lib
make
make DESTDIR=$LFS install
sed '/RTLDLIST=/s@/usr/lib@/lib@' -i $LFS/usr/bin/ldd
cd ../..

echo "Cross-toolchain build complete!"

EOF

chmod +x $LFS/build-lfs.sh
chown lfs:lfs $LFS/build-lfs.sh

log_info "Host preparation complete!"
log_info "Now run: su - lfs"
log_info "Then: /mnt/lfs/build-lfs.sh"