#!/bin/bash
# Build desktop environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/utils.sh"

PROFILE=${PROFILE:-xfce}
log_info "Building $PROFILE desktop environment"

# Copy profile customization
cp -r "$SCRIPT_DIR/../../profiles/$PROFILE/"* $LFS/

cat > $LFS/build-desktop.sh << "EOF"
#!/bin/bash

set -e
cd /sources

# Build GTK
echo "Building GTK..."
tar -xf gtk+-*.tar.xz
cd gtk+-*
mkdir build
cd build
meson setup --prefix=/usr --buildtype=release -Dintrospection=enabled -Ddemos=false -Dtests=false ..
ninja
ninja install
cd ../..

# XFCE specific
if [ "$PROFILE" = "xfce" ]; then
    echo "Building XFCE desktop..."

    # libxfce4util
    tar -xf libxfce4util-*.tar.bz2
    cd libxfce4util-*
    ./configure --prefix=/usr
    make -j$(nproc)
    make install
    cd ..

    # xfconf
    tar -xf xfconf-*.tar.bz2
    cd xfconf-*
    ./configure --prefix=/usr
    make -j$(nproc)
    make install
    cd ..

    # libxfce4ui
    tar -xf libxfce4ui-*.tar.bz2
    cd libxfce4ui-*
    ./configure --prefix=/usr
    make -j$(nproc)
    make install
    cd ..

    # exo
    tar -xf exo-*.tar.bz2
    cd exo-*
    ./configure --prefix=/usr
    make -j$(nproc)
    make install
    cd ..

    # garcon
    tar -xf garcon-*.tar.bz2
    cd garcon-*
    ./configure --prefix=/usr
    make -j$(nproc)
    make install
    cd ..

    # xfce4-panel
    tar -xf xfce4-panel-*.tar.bz2
    cd xfce4-panel-*
    ./configure --prefix=/usr
    make -j$(nproc)
    make install
    cd ..

    # thunar
    tar -xf thunar-*.tar.bz2
    cd thunar-*
    ./configure --prefix=/usr
    make -j$(nproc)
    make install
    cd ..

    # xfwm4
    tar -xf xfwm4-*.tar.bz2
    cd xfwm4-*
    ./configure --prefix=/usr
    make -j$(nproc)
    make install
    cd ..

    # xfce4-session
    tar -xf xfce4-session-*.tar.bz2
    cd xfce4-session-*
    ./configure --prefix=/usr
    make -j$(nproc)
    make install
    cd ..

    # xfce4-settings
    tar -xf xfce4-settings-*.tar.bz2
    cd xfce4-settings-*
    ./configure --prefix=/usr
    make -j$(nproc)
    make install
    cd ..

    # xfdesktop
    tar -xf xfdesktop-*.tar.bz2
    cd xfdesktop-*
    ./configure --prefix=/usr
    make -j$(nproc)
    make install
    cd ..
fi

# GNOME specific
if [ "$PROFILE" = "gnome" ]; then
    echo "Building GNOME desktop..."
    # GNOME build would go here (very large)
    echo "GNOME profile requires additional configuration"
fi

# LightDM
echo "Building LightDM..."
tar -xf lightdm-*.tar.gz
cd lightdm-*
mkdir build
cd build
meson setup --prefix=/usr --buildtype=release -Dlibdir=/usr/lib -Dlogind=systemd -Dliblightdm-qt5=false ..
ninja
ninja install
cd ../..

# LightDM GTK Greeter
tar -xf lightdm-gtk-greeter-*.tar.gz
cd lightdm-gtk-greeter-*
mkdir build
cd build
meson setup --prefix=/usr --buildtype=release ..
ninja
ninja install
cd ../..

# Configure LightDM
cat > /etc/lightdm/lightdm.conf << "LIGHTDM"
[LightDM]
greeter-session=lightdm-gtk-greeter

[Seat:*]
autologin-user=lfsuser
autologin-user-timeout=0
user-session=xfce

[XDMCPServer]
enabled=false
LIGHTDM

echo "Desktop build complete!"
EOF

chmod +x $LFS/build-desktop.sh

chroot "$LFS" /usr/bin/env -i \
    HOME=/root \
    TERM="$TERM" \
    PS1='(lfs chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin \
    PROFILE="$PROFILE" \
    /bin/bash /build-desktop.sh

log_info "Desktop build complete!"