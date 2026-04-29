#!/bin/bash
# GNOME desktop profile

set -e

log_info "Applying GNOME profile"

# Install GNOME components
cd /sources

# Track the build process
echo "Installing GNOME (this will take many hours)..."

# Meson and ninja already installed from base

# Install gtk-doc for building docs
tar -xf gtk-doc-*.tar.xz
cd gtk-doc-*
meson setup --prefix=/usr --buildtype=release build
ninja -C build
ninja -C build install
cd ..

# Install libxml2
tar -xf libxml2-*.tar.xz
cd libxml2-*
./configure --prefix=/usr --disable-static --with-history
make
make install
cd ..

# Install gobject-introspection
tar -xf gobject-introspection-*.tar.xz
cd gobject-introspection-*
meson setup --prefix=/usr --buildtype=release build
ninja -C build
ninja -C build install
cd ..

# Install GLib (already done in desktop build)

# Install GNOME Shell dependencies
echo "GNOME profile requires many more packages..."
echo "See BLFS book for complete GNOME build"

# Configure GDM
cat > /etc/gdm/custom.conf << "GDM"
[daemon]
AutomaticLoginEnable=True
AutomaticLogin=lfsuser

[security]

[xdmcp]

[chooser]

[debug]
GDM

echo "GNOME profile partially applied (requires full BLFS GNOME build)"