#!/bin/bash
# Build cross-toolchain (run as lfs user)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/utils.sh"

LFS=${LFS:-/mnt/lfs}
LFS_TGT=${LFS_TGT:-$(uname -m)-lfs-linux-gnu}
NUM_JOBS=${NUM_JOBS:-$(nproc)}
LC_ALL=POSIX

log_info "Building cross-toolchain as $(whoami)"

if [ "$EUID" -eq 0 ]; then
    log_error "This script must NOT be run as root"
    exit 1
fi

cd $LFS/sources

# Binutils (first pass)
log_info "Building binutils (pass 1)"
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
make -j$NUM_JOBS
make install
cd ../..

# GCC (first pass)
log_info "Building GCC (pass 1)"
tar -xf gcc-*.tar.xz
cd gcc-*
tar -xf ../mpfr-*.tar.xz
mv -v mpfr-* mpfr
tar -xf ../gmp-*.tar.xz
mv -v gmp-* gmp
tar -xf ../mpc-*.tar.xz
mv -v mpc-* mpc
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
make -j$NUM_JOBS
make install
cd ../..

# Linux API Headers
log_info "Installing Linux API headers"
tar -xf linux-*.tar.xz
cd linux-*
make mrproper
make headers
find usr/include -type f ! -name '*.h' -delete
cp -rv usr/include $LFS/usr
cd ..

# Glibc
log_info "Building Glibc"
tar -xf glibc-*.tar.xz
cd glibc-*
if [ "$(uname -m)" = "x86_64" ]; then
    ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64
    ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64/ld-lsb-x86-64.so.3
fi
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
make -j$NUM_JOBS
make DESTDIR=$LFS install
sed '/RTLDLIST=/s@/usr/lib@/lib@' -i $LFS/usr/bin/ldd
cp -v ../nscd/nscd.conf $LFS/etc/nscd.conf
mkdir -pv $LFS/var/cache/nscd
cd ../..

# GCC (second pass)
log_info "Building GCC (pass 2)"
tar -xf gcc-*.tar.xz
cd gcc-*
case $(uname -m) in
  x86_64)
    sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
  ;;
esac
mkdir -v build
cd build
../configure --build=$(../config.guess) \
             --host=$LFS_TGT \
             --target=$LFS_TGT \
             LDFLAGS_FOR_TARGET=-L$PWD/$LFS_TGT/libgcc \
             --prefix=/usr \
             --with-build-sysroot=$LFS \
             --enable-default-pie \
             --enable-default-ssp \
             --disable-nls \
             --disable-multilib \
             --disable-libatomic \
             --disable-libgomp \
             --disable-libquadmath \
             --disable-libsanitizer \
             --disable-libssp \
             --disable-libvtv \
             --enable-languages=c,c++
make -j$NUM_JOBS
make DESTDIR=$LFS install
ln -sv gcc $LFS/usr/bin/cc
cd ../..

log_info "Cross-toolchain build complete!"