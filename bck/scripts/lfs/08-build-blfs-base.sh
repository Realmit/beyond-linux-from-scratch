#!/bin/bash
# Build BLFS base system

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/utils.sh"

log_info "Building BLFS base system"

cat > $LFS/build-blfs.sh << "EOF"
#!/bin/bash

set -e
cd /sources

# Xorg libraries
echo "Building Xorg libraries..."
tar -xf libxcb-*.tar.xz
cd libxcb-*
./configure --prefix=/usr --sysconfdir=/etc --disable-static
make -j$(nproc)
make install
cd ..

# Mesa
echo "Building Mesa..."
tar -xf mesa-*.tar.xz
cd mesa-*
mkdir build
cd build
meson setup --prefix=/usr --buildtype=release -Dgallium-drivers=auto -Dvulkan-drivers=auto -Dshared-glapi=enabled -Dopengl=true -Degl=enabled -Dgbm=enabled -Dosmesa=false -Ddri3=enabled ..
ninja
ninja install
cd ../..

# ALSA
echo "Building ALSA..."
tar -xf alsa-lib-*.tar.bz2
cd alsa-lib-*
./configure --prefix=/usr
make -j$(nproc)
make install
cd ..

# PulseAudio
echo "Building PulseAudio..."
tar -xf pulseaudio-*.tar.xz
cd pulseaudio-*
mkdir build
cd build
meson setup --prefix=/usr --buildtype=release -Ddaemon=true -Ddoxygen=false -Dman=false -Dtests=false ..
ninja
ninja install
cd ../..

# Fonts
echo "Installing fonts..."
tar -xf dejavu-fonts-ttf-*.tar.bz2
cd dejavu-fonts-ttf-*
cp -v *.ttf /usr/share/fonts/TTF/
cd ..

# Bluetooth support
echo "Building BlueZ..."
tar -xf bluez-*.tar.xz
cd bluez-*
./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --enable-library
make -j$(nproc)
make install
cd ..

echo "BLFS base build complete!"
EOF

chmod +x $LFS/build-blfs.sh

chroot "$LFS" /usr/bin/env -i \
    HOME=/root \
    TERM="$TERM" \
    PS1='(lfs chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin \
    /bin/bash /build-blfs.sh

log_info "BLFS base system build complete!"