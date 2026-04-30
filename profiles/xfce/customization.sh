#!/bin/bash
# XFCE Desktop Profile for LFS
# Lightweight XFCE 4.20 desktop environment setup

set -e

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[0;34m[SUCCESS]\033[0m $1"; }
log_warning() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

# ============================================================================
# XFCE SPECIFIC CONFIGURATION
# ============================================================================

XFCE_VERSION="4.20"
NUM_JOBS=${NUM_JOBS:-$(nproc)}
PACKAGE_LIST="profiles/xfce/packages.list"

# ============================================================================
# INSTALL XFCE COMPONENTS
# ============================================================================
install_xfce() {
    log_info "Installing XFCE ${XFCE_VERSION} desktop environment..."

    cd /sources

    # Core XFCE packages
    local core_packages=(
        "libxfce4util"
        "xfconf"
        "libxfce4ui"
        "exo"
        "garcon"
        "xfce4-panel"
        "xfce4-session"
        "xfce4-settings"
        "xfwm4"
        "xfdesktop"
        "thunar"
        "xfce4-appfinder"
    )

    for pkg in "${core_packages[@]}"; do
        if [ -f "${pkg}-*.tar.bz2" ]; then
            log_info "Building $pkg..."
            tar -xf ${pkg}-*.tar.bz2
            cd ${pkg}-*

            ./configure --prefix=/usr
            make -j$NUM_JOBS
            make install

            cd ..
        fi
    done

    log_success "XFCE core components installed"
}

# ============================================================================
# INSTALL XFCE APPLICATIONS
# ============================================================================
install_xfce_apps() {
    log_info "Installing XFCE applications..."

    cd /sources

    local applications=(
        "xfce4-terminal"
        "xfce4-taskmanager"
        "xfce4-screenshooter"
        "xfce4-power-manager"
        "xfce4-notifyd"
        "ristretto"
        "mousepad"
        "orage"
        "parole"
        "gigolo"
    )

    for app in "${applications[@]}"; do
        if [ -f "${app}-*.tar.bz2" ]; then
            log_info "Building $app..."
            tar -xf ${app}-*.tar.bz2
            cd ${app}-*

            ./configure --prefix=/usr
            make -j$NUM_JOBS
            make install

            cd ..
        fi
    done

    log_success "XFCE applications installed"
}

# ============================================================================
# INSTALL XFCE PLUGINS
# ============================================================================
install_xfce_plugins() {
    log_info "Installing XFCE panel plugins..."

    cd /sources

    local plugins=(
        "xfce4-whiskermenu-plugin"
        "xfce4-docklike-plugin"
        "xfce4-statusnotifier-plugin"
        "xfce4-cpugraph-plugin"
        "xfce4-netload-plugin"
        "xfce4-systemload-plugin"
        "xfce4-weather-plugin"
        "xfce4-clipman-plugin"
        "thunar-archive-plugin"
    )

    for plugin in "${plugins[@]}"; do
        if [ -f "${plugin}-*.tar.bz2" ]; then
            log_info "Building $plugin..."
            tar -xf ${plugin}-*.tar.bz2
            cd ${plugin}-*

            ./configure --prefix=/usr
            make -j$NUM_JOBS
            make install

            cd ..
        fi
    done

    log_success "XFCE plugins installed"
}

# ============================================================================
# CONFIGURE LIGHTDM (Display Manager)
# ============================================================================
configure_lightdm() {
    log_info "Configuring LightDM for XFCE..."

    # Create LightDM configuration directory
    mkdir -p /etc/lightdm

    # Main LightDM configuration
    cat > /etc/lightdm/lightdm.conf << 'EOF'
[LightDM]
greeter-session=lightdm-gtk-greeter
user-session=xfce

[Seat:*]
autologin-user=lfsuser
autologin-user-timeout=0
session-wrapper=/etc/X11/Xsession
user-session=xfce
greeter-session=lightdm-gtk-greeter

[XDMCPServer]
enabled=false

[VNCServer]
enabled=false
EOF

    # GTK Greeter configuration
    cat > /etc/lightdm/lightdm-gtk-greeter.conf << 'EOF'
[greeter]
background=/usr/share/backgrounds/xfce/xfce-stripes.png
theme-name=Adwaita
icon-theme-name=Adwaita
font-name=Sans 10
clock-format=%H:%M
indicators=~host;~spacer;~clock;~spacer;~session;~language;~a11y;~power
show-indicators=~session;~language;~a11y
EOF

    # Enable LightDM service
    if command -v systemctl &> /dev/null; then
        systemctl enable lightdm
        systemctl set-default graphical.target
    fi

    log_success "LightDM configured"
}

# ============================================================================
# CONFIGURE XFCE SETTINGS
# ============================================================================
configure_xfce() {
    log_info "Configuring XFCE desktop settings..."

    # Create configuration directories for default user
    mkdir -p /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/

    # Panel configuration
    cat > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="panels" type="uint" value="1">
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
        <value type="int" value="6"/>
        <value type="int" value="7"/>
        <value type="int" value="8"/>
      </property>
    </property>
  </property>
</channel>
EOF

    # Desktop settings
    cat > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitor0" type="empty">
        <property name="image-path" type="string" value="/usr/share/backgrounds/xfce/xfce-stripes.png"/>
        <property name="image-style" type="int" value="5"/>
        <property name="image-show" type="bool" value="true"/>
      </property>
    </property>
  </property>
</channel>
EOF

    # Window manager settings
    cat > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="Default"/>
    <property name="title_font" type="string" value="Sans Bold 9"/>
    <property name="button_layout" type="string" value="O|SHMC"/>
    <property name="button_offset" type="int" value="0"/>
    <property name="easy_click" type="string" value="Alt"/>
    <property name="focus_delay" type="int" value="250"/>
    <property name="focus_hint" type="bool" value="true"/>
    <property name="placement_ratio" type="int" value="20"/>
    <property name="raise_on_focus" type="bool" value="false"/>
    <property name="wrap_windows" type="bool" value="false"/>
    <property name="wrap_workspaces" type="bool" value="false"/>
    <property name="click_to_focus" type="bool" value="true"/>
  </property>
</channel>
EOF

    # GTK settings
    mkdir -p /etc/skel/.config/gtk-3.0
    cat > /etc/skel/.config/gtk-3.0/settings.ini << 'EOF'
[Settings]
gtk-theme-name=Adwaita
gtk-icon-theme-name=Adwaita
gtk-font-name=Sans 10
gtk-cursor-theme-name=Adwaita
gtk-toolbar-style=GTK_TOOLBAR_ICONS
gtk-enable-event-sounds=0
gtk-enable-input-feedback-sounds=0
EOF

    # XFCE keyboard shortcuts
    cat > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-keyboard-shortcuts" version="1.0">
  <property name="commands" type="empty">
    <property name="default" type="empty">
      <property name="&lt;Primary&gt;&lt;Alt&gt;t" type="string" value="xfce4-terminal"/>
      <property name="&lt;Primary&gt;&lt;Alt&gt;Delete" type="string" value="xfce4-session-logout"/>
      <property name="&lt;Super&gt;e" type="string" value="thunar"/>
      <property name="&lt;Super&gt;f" type="string" value="firefox"/>
      <property name="&lt;Super&gt;r" type="string" value="xfce4-appfinder"/>
    </property>
  </property>
</channel>
EOF

    log_success "XFCE settings configured"
}

# ============================================================================
# SETUP XFCE BACKGROUNDS
# ============================================================================
setup_backgrounds() {
    log_info "Setting up XFCE backgrounds..."

    mkdir -p /usr/share/backgrounds/xfce

    cd /usr/share/backgrounds/xfce
    if [ ! -f "xfce-stripes.png" ]; then
        # Create simple gradient background
        convert -size 1920x1080 gradient:blue-grey xfce-stripes.png 2>/dev/null || true
    fi

    log_success "Backgrounds configured"
}

# ============================================================================
# CLEANUP
# ============================================================================
cleanup() {
    log_info "Cleaning up temporary files..."

    cd /sources
    rm -rf libxfce4util-* xfconf-* libxfce4ui-* exo-* garcon-*
    rm -rf xfce4-panel-* xfce4-session-* xfce4-settings-* xfwm4-* xfdesktop-* thunar-*
    rm -rf xfce4-* mousepad-* ristretto-* parole-*

    log_success "Cleanup complete"
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    log_info "========================================="
    log_info "XFCE Desktop Installation"
    log_info "========================================="

    install_xfce
    install_xfce_apps
    install_xfce_plugins
    configure_lightdm
    configure_xfce
    setup_backgrounds
    cleanup

    log_success "========================================="
    log_success "XFCE Desktop Installation Complete!"
    log_success "========================================="
    echo ""
    echo "XFCE $XFCE_VERSION has been installed successfully."
    echo ""
    echo "To start XFCE:"
    echo "  1. Reboot your system"
    echo "  2. Login with your user account"
    echo "  3. XFCE will start automatically"
    echo ""
    echo "Default login: lfsuser / lfsuser123"
    echo "========================================="
}

# Run main function
main "$@"