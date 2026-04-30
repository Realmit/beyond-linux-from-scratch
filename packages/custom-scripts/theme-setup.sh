#!/bin/bash
# Theme setup script for LFS desktop
# Runs after desktop installation

set -e

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[0;34m[SUCCESS]\033[0m $1"; }

# ----------------------------------------------------------------------------
# INSTALL FONTS
# ----------------------------------------------------------------------------
install_fonts() {
    log_info "Installing fonts..."

    # Create font directories
    mkdir -p /usr/share/fonts/{TTF,OTF,Type1}

    cd /sources

    # Download and install Cascadia Code (Nerd Font)
    if [ ! -f CascadiaCode.zip ]; then
        wget https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/CascadiaCode.zip
    fi
    unzip -o CascadiaCode.zip -d /usr/share/fonts/TTF/

    # Download and install Noto Fonts
    if [ ! -f NotoSans-hinted.zip ]; then
        wget https://noto-website-2.storage.googleapis.com/pkgs/NotoSans-hinted.zip
    fi
    unzip -o NotoSans-hinted.zip -d /usr/share/fonts/TTF/

    # Update font cache
    fc-cache -fv

    log_success "Fonts installed"
}

# ----------------------------------------------------------------------------
# INSTALL ICON THEMES
# ----------------------------------------------------------------------------
install_icon_themes() {
    log_info "Installing icon themes..."

    cd /sources

    # Papirus icon theme
    if [ ! -f Papirus.tar.gz ]; then
        wget https://github.com/PapirusDevelopmentTeam/papirus-icon-theme/archive/20231201/Papirus-20231201.tar.gz
    fi
    tar -xzf Papirus-20231201.tar.gz
    cd papirus-icon-theme-20231201
    ./install.sh
    cd ..

    # Adwaita (already installed with GTK)

    log_success "Icon themes installed"
}

# ----------------------------------------------------------------------------
# INSTALL GTK THEMES
# ----------------------------------------------------------------------------
install_gtk_themes() {
    log_info "Installing GTK themes..."

    cd /sources

    # Arc Theme
    if [ ! -f Arc-Dark.tar.xz ]; then
        wget https://github.com/jnsh/arc-theme/archive/refs/tags/20221218.tar.gz -O Arc-Dark.tar.gz
    fi
    tar -xzf Arc-Dark.tar.gz
    cd arc-theme-20221218
    ./autogen.sh --prefix=/usr
    make -j$(nproc)
    make install
    cd ..

    # Matcha theme
    if [ ! -f Matcha.tar.xz ]; then
        wget https://github.com/vinceliuice/Matcha-theme/archive/2023-10-01.tar.gz -O Matcha.tar.gz
    fi
    tar -xzf Matcha.tar.gz
    cd Matcha-theme-2023-10-01
    ./install.sh
    cd ..

    log_success "GTK themes installed"
}

# ----------------------------------------------------------------------------
# SET DEFAULT THEME FOR ALL USERS
# ----------------------------------------------------------------------------
set_default_theme() {
    log_info "Setting default theme..."

    # For root
    mkdir -p /root/.config/gtk-3.0
    cat > /root/.config/gtk-3.0/settings.ini << 'EOF'
[Settings]
gtk-theme-name=Arc-Dark
gtk-icon-theme-name=Papirus
gtk-font-name=Noto Sans 10
gtk-cursor-theme-name=Adwaita
gtk-toolbar-style=GTK_TOOLBAR_BOTH_HORIZ
gtk-toolbar-icon-size=GTK_ICON_SIZE_LARGE_TOOLBAR
gtk-button-images=1
gtk-menu-images=1
gtk-enable-event-sounds=0
gtk-enable-input-feedback-sounds=0
gtk-xft-antialias=1
gtk-xft-hinting=1
gtk-xft-hintstyle=hintfull
gtk-xft-rgba=rgb
EOF

    # For lfsuser (template for new users)
    mkdir -p /etc/skel/.config/gtk-3.0
    cp /root/.config/gtk-3.0/settings.ini /etc/skel/.config/gtk-3.0/

    # For existing lfsuser
    if [ -d /home/lfsuser ]; then
        mkdir -p /home/lfsuser/.config/gtk-3.0
        cp /root/.config/gtk-3.0/settings.ini /home/lfsuser/.config/gtk-3.0/
        chown -R lfsuser:lfsuser /home/lfsuser/.config
    fi

    log_success "Default theme configured"
}

# ----------------------------------------------------------------------------
# SET WALLPAPER
# ----------------------------------------------------------------------------
set_wallpaper() {
    log_info "Setting default wallpaper..."

    mkdir -p /usr/share/backgrounds

    # Download a nice default wallpaper
    cd /usr/share/backgrounds

    if [ ! -f default.jpg ]; then
        wget -O default.jpg https://images.pexels.com/photos/147411/italy-mountains-dawn-daybreak-147411.jpeg
    fi

    # For XFCE
    if [ -d /etc/xdg/xfce4 ]; then
        cat > /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitor0" type="empty">
        <property name="image-path" type="string" value="/usr/share/backgrounds/default.jpg"/>
        <property name="image-style" type="int" value="5"/>
        <property name="image-show" type="bool" value="true"/>
      </property>
    </property>
  </property>
</channel>
EOF
    fi

    log_success "Wallpaper configured"
}

# ----------------------------------------------------------------------------
# CONFIGURE GTK FOR ALL ENVIRONMENTS
# ----------------------------------------------------------------------------
configure_gtk() {
    log_info "Configuring GTK settings..."

    # GTK 2 configuration
    cat > /etc/gtk-2.0/gtkrc << 'EOF'
gtk-theme-name="Arc-Dark"
gtk-icon-theme-name="Papirus"
gtk-font-name="Noto Sans 10"
gtk-toolbar-style=GTK_TOOLBAR_ICONS
gtk-enable-event-sounds=0
gtk-enable-input-feedback-sounds=0
EOF

    # GTK 4 configuration (if available)
    if [ -d /etc/gtk-4.0 ]; then
        cat > /etc/gtk-4.0/settings.ini << 'EOF'
[Settings]
gtk-theme-name=Arc-Dark
gtk-icon-theme-name=Papirus
gtk-font-name=Noto Sans 10
EOF
    fi

    log_success "GTK configured"
}

# ----------------------------------------------------------------------------
# CONFIGURE QT THEMES (for Qt applications)
# ----------------------------------------------------------------------------
configure_qt() {
    log_info "Configuring Qt themes..."

    # Install qt5ct if available
    if [ -f /usr/bin/qt5ct ]; then
        cat > /etc/xdg/qt5ct/qt5ct.conf << 'EOF'
[Appearance]
style=Breeze
color_scheme=dark
custom_palette=false
icon_theme=Papirus
EOF
    fi

    log_success "Qt configured"
}

# ----------------------------------------------------------------------------
# MAIN
# ----------------------------------------------------------------------------
main() {
    log_info "=== THEME SETUP ==="

    install_fonts
    install_icon_themes
    install_gtk_themes
    configure_gtk
    configure_qt
    set_default_theme
    set_wallpaper

    log_success "Theme setup complete!"
}

main "$@"