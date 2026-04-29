#!/bin/bash
# XFCE desktop customization script

# Install XFCE desktop components
install_xfce() {
    log_info "Installing XFCE desktop environment"

    # Core XFCE packages
    packages=(
        "xfce4-4.18.tar.bz2"
        "xfce4-dev-tools-4.18.tar.bz2"
        "libxfce4ui-4.18.tar.bz2"
        "libxfce4util-4.18.tar.bz2"
        "xfce4-panel-4.18.tar.bz2"
        "xfce4-session-4.18.tar.bz2"
        "xfce4-settings-4.18.tar.bz2"
        "xfconf-4.18.tar.bz2"
        "xfwm4-4.18.tar.bz2"
        "thunar-4.18.tar.bz2"
        "tumbler-4.18.tar.bz2"
    )

    for pkg in "${packages[@]}"; do
        extract_archive "/sources/$pkg"
        build_package "${pkg%.tar.*}" "./configure --prefix=/usr && make && make install"
    done
}

# Configure lightdm
configure_lightdm() {
    log_info "Configuring LightDM"

    cat > /etc/lightdm/lightdm.conf << "EOF"
[Seat:*]
autologin-user=lfsuser
autologin-user-timeout=0
greeter-session=lightdm-gtk-greeter
user-session=xfce
EOF

    cat > /etc/lightdm/lightdm-gtk-greeter.conf << "EOF"
[greeter]
background=/usr/share/backgrounds/default.png
theme-name=Adwaita
icon-theme-name=Adwaita
font-name=Sans 10
clock-format=%H:%M
EOF
}

# Install common applications
install_applications() {
    log_info "Installing common applications"

    # Web browser
    cd /sources
    wget https://ftp.mozilla.org/pub/firefox/releases/122.0/source/firefox-122.0.source.tar.xz
    tar -xf firefox-122.0.source.tar.xz
    cd firefox-122.0

    # Configure and build Firefox
    ./mach configure --prefix=/usr
    ./mach build
    ./mach install

    # Office suite
    cd /sources
    wget https://download.documentfoundation.org/libreoffice/stable/7.6.4/src/libreoffice-7.6.4.1.tar.xz
    tar -xf libreoffice-7.6.4.1.tar.xz
    cd libreoffice-7.6.4.1
    ./autogen.sh --prefix=/usr
    make -j$NUM_JOBS
    make install

    # Multimedia
    apt-get install -y vlc gimp inkscape audacity
}

# Configure desktop appearance
configure_desktop_appearance() {
    log_info "Applying desktop customizations"

    # Set default theme
    mkdir -p /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/

    cat > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml << "EOF"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Adwaita"/>
    <property name="IconThemeName" type="string" value="Adwaita"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="CursorThemeName" type="string" value="Adwaita"/>
    <property name="FontName" type="string" value="Sans 10"/>
  </property>
</channel>
EOF

    # Set panel configuration
    cat > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml << "EOF"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="panels" type="uint" value="1"/>
  <property name="panel-1" type="empty">
    <property name="position" type="string" value="p=6;x=0;y=0"/>
    <property name="length" type="uint" value="100"/>
    <property name="position-locked" type="bool" value="true"/>
    <property name="plugin-ids" type="array">
      <value type="int" value="1"/>
      <value type="int" value="2"/>
      <value type="int" value="3"/>
      <value type="int" value="4"/>
      <value type="int" value="5"/>
    </property>
  </property>
</channel>
EOF
}

# Main execution
main() {
    install_xfce
    configure_lightdm
    install_applications
    configure_desktop_appearance

    log_info "Desktop customization complete"
}

main