#!/bin/bash
# KDE Plasma Desktop Profile for LFS
# Full KDE Plasma 6 desktop environment setup

set -e

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[0;34m[SUCCESS]\033[0m $1"; }
log_warning() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

# ============================================================================
# KDE SPECIFIC CONFIGURATION
# ============================================================================

KDE_VERSION="6"
QT_VERSION="6"
NUM_JOBS=${NUM_JOBS:-$(nproc)}
PACKAGE_LIST="profiles/kde/packages.list"

# ============================================================================
# BUILD QT6 FRAMEWORK
# ============================================================================
build_qt6() {
    log_info "Building Qt6 framework (this will take a very long time)..."

    cd /sources

    # Qt6 base
    if [ -f "qt6-base-*.tar.xz" ]; then
        log_info "Building Qt6 Base..."
        tar -xf qt6-base-*.tar.xz
        cd qt6-base-*

        mkdir -p build
        cd build
        ../configure -prefix /usr \
                     -release \
                     -shared \
                     -nomake examples \
                     -nomake tests \
                     -confirm-license \
                     -opensource \
                     -qt-doubleconversion \
                     -qt-pcre \
                     -qt-zlib \
                     -qt-libpng \
                     -qt-libjpeg \
                     -qt-freetype \
                     -qt-harfbuzz \
                     -qt-sqlite \
                     -openssl-linked \
                     -dbus-linked \
                     -glib \
                     -icu \
                     -xcb \
                     -xcb-xlib \
                     -xkbcommon \
                     -wayland
        make -j$NUM_JOBS
        make install
        cd ../..
    fi

    # Additional Qt6 modules
    local qt_modules=(
        "qt6-declarative"
        "qt6-tools"
        "qt6-multimedia"
        "qt6-svg"
        "qt6-quickcontrols"
        "qt6-webengine"
        "qt6-wayland"
    )

    for module in "${qt_modules[@]}"; do
        if [ -f "${module}-*.tar.xz" ]; then
            log_info "Building $module..."
            tar -xf ${module}-*.tar.xz
            cd ${module}-*

            mkdir -p build
            cd build
            ../configure -prefix /usr
            make -j$NUM_JOBS
            make install
            cd ../..
        fi
    done

    log_success "Qt6 built successfully"
}

# ============================================================================
# BUILD KDE FRAMEWORKS
# ============================================================================
build_kde_frameworks() {
    log_info "Building KDE Frameworks 6..."

    cd /sources

    # Core frameworks first (order matters!)
    local core_frameworks=(
        "extra-cmake-modules"
        "kf6-kcoreaddons"
        "kf6-kconfig"
        "kf6-ki18n"
        "kf6-kcrash"
        "kf6-kdbusaddons"
        "kf6-kdoctools"
        "kf6-kwindowsystem"
        "kf6-solid"
        "kf6-kdeclarative"
        "kf6-kio"
        "kf6-knotifications"
    )

    for framework in "${core_frameworks[@]}"; do
        if [ -f "${framework}-*.tar.xz" ]; then
            log_info "Building $framework..."
            tar -xf ${framework}-*.tar.xz
            cd ${framework}-*

            mkdir -p build
            cd build
            cmake -DCMAKE_INSTALL_PREFIX=/usr \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_TESTING=OFF \
                  ..
            make -j$NUM_JOBS
            make install
            cd ../..
        fi
    done

    log_success "KDE Frameworks built"
}

# ============================================================================
# BUILD KDE PLASMA
# ============================================================================
build_kde_plasma() {
    log_info "Building KDE Plasma Shell..."

    cd /sources

    local plasma_components=(
        "libksysguard"
        "kwayland-server"
        "plasma-wayland-protocols"
        "plasma-workspace"
        "plasma-desktop"
        "plasma-systemmonitor"
        "plasma-nm"
        "plasma-pa"
        "plasma-firewall"
        "plasma-disks"
        "plasma-vault"
        "kdeplasma-addons"
        "systemsettings"
        "kinfocenter"
        "sddm"
        "sddm-kcm"
    )

    for component in "${plasma_components[@]}"; do
        if [ -f "${component}-*.tar.xz" ]; then
            log_info "Building $component..."
            tar -xf ${component}-*.tar.xz
            cd ${component}-*

            mkdir -p build
            cd build
            cmake -DCMAKE_INSTALL_PREFIX=/usr \
                  -DCMAKE_BUILD_TYPE=Release \
                  ..
            make -j$NUM_JOBS
            make install
            cd ../..
        fi
    done

    log_success "KDE Plasma built"
}

# ============================================================================
# BUILD KDE APPLICATIONS
# ============================================================================
build_kde_apps() {
    log_info "Building KDE applications..."

    cd /sources

    local applications=(
        "dolphin"
        "konsole"
        "kate"
        "kwrite"
        "gwenview"
        "okular"
        "ark"
        "kcalc"
        "kfind"
        "kgpg"
        "kwalletmanager"
        "spectacle"
        "kamoso"
        "elisa"
        "kdenlive"
        "krita"
    )

    for app in "${applications[@]}"; do
        if [ -f "${app}-*.tar.xz" ]; then
            log_info "Building $app..."
            tar -xf ${app}-*.tar.xz
            cd ${app}-*

            mkdir -p build
            cd build
            cmake -DCMAKE_INSTALL_PREFIX=/usr \
                  -DCMAKE_BUILD_TYPE=Release \
                  ..
            make -j$NUM_JOBS
            make install
            cd ../..
        fi
    done

    log_success "KDE applications built"
}

# ============================================================================
# CONFIGURE SDDM (Display Manager)
# ============================================================================
configure_sddm() {
    log_info "Configuring SDDM for KDE Plasma..."

    # Create SDDM configuration directory
    mkdir -p /etc/sddm.conf.d

    # Main SDDM configuration
    cat > /etc/sddm.conf.d/kde_settings.conf << 'EOF'
[Autologin]
User=lfsuser
Session=plasma

[Theme]
Current=breeze
CursorTheme=breeze_cursors

[Users]
MaximumUid=60000
MinimumUid=1000

[General]
HaltCommand=/usr/bin/systemctl poweroff
RebootCommand=/usr/bin/systemctl reboot
Numlock=on

[Wayland]
EnableHiDPI=true
SessionDir=/usr/share/wayland-sessions

[X11]
EnableHiDPI=true
SessionDir=/usr/share/xsessions
EOF

    # Create Plasma session file
    mkdir -p /usr/share/wayland-sessions
    cat > /usr/share/wayland-sessions/plasma.desktop << 'EOF'
[Desktop Entry]
Name=Plasma (Wayland)
Comment=Plasma by KDE
Exec=/usr/bin/startplasma-wayland
Type=Application
DesktopNames=KDE
X-GDM-SessionRegisters=true
EOF

    mkdir -p /usr/share/xsessions
    cat > /usr/share/xsessions/plasma.desktop << 'EOF'
[Desktop Entry]
Name=Plasma
Comment=Plasma by KDE
Exec=/usr/bin/startplasma-x11
Type=Application
DesktopNames=KDE
X-GDM-SessionRegisters=true
EOF

    # Enable SDDM service
    if command -v systemctl &> /dev/null; then
        systemctl enable sddm
        systemctl set-default graphical.target
    fi

    log_success "SDDM configured"
}

# ============================================================================
# CONFIGURE KDE SETTINGS
# ============================================================================
configure_kde_settings() {
    log_info "Configuring KDE Plasma settings..."

    # Create default configuration for new users
    mkdir -p /etc/skel/.config

    # Plasma workspace configuration
    cat > /etc/skel/.config/plasmarc << 'EOF'
[ActionPlugins]
Baloo=Disabled

[Freespace]
NotifyPercent=5

[General]
closeOnDoubleClick=false
killAllWindows=false
singleClick=false

[Theme]
name=breeze-dark

[Weather]
Units=metric
EOF

    # KWin configuration (window manager)
    cat > /etc/skel/.config/kwinrc << 'EOF'
[Compositing]
OpenGLIsUnsafe=false
Enabled=true
Backend=OpenGL
VSync=true
MaxFPS=120

[Desktops]
Number=4
Rows=1

[Plugins]
blurEnabled=true
kwin4_effect_blurEnabled=true
kwin4_effect_logoutEnabled=true
kwin4_effect_maximizeEnabled=true
kwin4_effect_minimizeEnabled=true
kwin4_effect_scaleEnabled=true
kwin4_effect_slidingpopupsEnabled=true
kwin4_effect_taskbarthumbnailEnabled=true

[TabBox]
Layout=compact
Mode=DesktopMode
ShowTabBox=true
WrapMode=Wrap

[Windows]
Placement=Smart
BorderlessMaximizedWindows=true
RollOverDesktops=false
SeparateScreenFocus=false
FocusPolicy=ClickToFocus
MoveMode=Opaque
ResizeMode=Opaque
EO

    # Dolphin settings
    mkdir -p /etc/skel/.local/share/kxmlgui5/dolphin
    mkdir -p /etc/skel/.config/dolphinrc

    # Konsole settings
    mkdir -p /etc/skel/.local/share/konsole
    cat > /etc/skel/.config/konsolerc << 'EOF'
[Desktop Entry]
DefaultProfile=Profile 1

[Favorite Profiles]
FavoriteList=

[TabBar]
TabBarVisibility=Always

[UI]
ShowMenuBarByDefault=false
ShowStatusBarByDefault=true
EOF

    # Create profile for konsole
    cat > /etc/skel/.local/share/konsole/Profile\ 1.profile << 'EOF'
[Appearance]
ColorScheme=WhiteOnBlack
Font=Hack,10,-1,5,50,0,0,0,0,0

[General]
Command=/bin/bash
Environment=
Name=Profile 1
Parent=FALLBACK/
TerminalColumns=80
TerminalRows=24
EOF

    log_success "KDE settings configured"
}

# ============================================================================
# SETUP KDE BACKGROUNDS
# ============================================================================
setup_backgrounds() {
    log_info "Setting up KDE backgrounds..."

    mkdir -p /usr/share/wallpapers

    # Download KDE Plasma 6 default wallpaper
    cd /usr/share/wallpapers
    if [ ! -f "plasma-stripes.png" ]; then
        wget -q https://cdn.kde.org/plasma/wallpapers/plasma-stripes.png 2>/dev/null || true
    fi

    # Set default wallpaper via configuration
    mkdir -p /etc/skel/.local/share/plasma/wallpapers

    log_success "Backgrounds configured"
}

# ============================================================================
# INSTALL BREEZE ICONS
# ============================================================================
setup_breeze_icons() {
    log_info "Installing Breeze icon theme..."

    cd /sources

    if [ -f "breeze-icons-*.tar.xz" ]; then
        tar -xf breeze-icons-*.tar.xz
        cd breeze-icons-*
        mkdir -p build
        cd build
        cmake -DCMAKE_INSTALL_PREFIX=/usr ..
        make -j$NUM_JOBS
        make install
        cd ../..
    fi

    log_success "Breeze icons installed"
}

# ============================================================================
# CONFIGURE KDE WALLET
# ============================================================================
configure_kwallet() {
    log_info "Configuring KDE Wallet..."

    # Create PAM configuration for kwallet
    if [ -f /etc/pam.d/sddm ]; then
        if ! grep -q "pam_kwallet" /etc/pam.d/sddm; then
            sed -i '/auth.*required.*pam_permit.so/a auth    optional    pam_kwallet5.so' /etc/pam.d/sddm
            sed -i '/session.*optional.*pam_kwallet/a session optional    pam_kwallet5.so auto_start' /etc/pam.d/sddm
        fi
    fi

    log_success "KDE Wallet configured"
}

# ============================================================================
# ENABLE KDE SERVICES
# ============================================================================
enable_kde_services() {
    log_info "Enabling KDE services..."

    if command -v systemctl &> /dev/null; then
        # Enable SDDM (already done)
        systemctl enable sddm

        # Enable KDE-specific services
        systemctl enable kdeconnect
        systemctl enable plasma-powerdevil

        log_success "KDE services enabled"
    fi
}

# ============================================================================
# CLEANUP
# ============================================================================
cleanup() {
    log_info "Cleaning up temporary files..."

    cd /sources
    rm -rf qt6-* kf6-* plasma-* dolphin-* konsole-* kate-* 2>/dev/null || true

    # Remove build directories
    rm -rf */build 2>/dev/null || true

    log_success "Cleanup complete"
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    log_info "========================================="
    log_info "KDE Plasma Desktop Installation"
    log_info "========================================="
    log_warning "This will take MANY hours (8-12 hours)..."
    echo ""

    build_qt6
    build_kde_frameworks
    build_kde_plasma
    build_kde_apps
    setup_breeze_icons
    configure_sddm
    configure_kde_settings
    setup_backgrounds
    configure_kwallet
    enable_kde_services
    cleanup

    log_success "========================================="
    log_success "KDE Plasma Desktop Installation Complete!"
    log_success "========================================="
    echo ""
    echo "KDE Plasma $KDE_VERSION has been installed successfully."
    echo ""
    echo "To start KDE Plasma:"
    echo "  1. Reboot your system"
    echo "  2. Login with your user account"
    echo "  3. Select 'Plasma' from the session menu"
    echo "  4. KDE Plasma will start"
    echo ""
    echo "Default login: lfsuser / lfsuser123"
    echo ""
    echo "Keyboard shortcuts:"
    echo "  Alt + F2        - Run command"
    echo "  Alt + Space     - Application launcher"
    echo "  Super (Win)     - Application menu"
    echo "  Ctrl + Alt + T  - Terminal"
    echo "  Alt + Tab       - Switch windows"
    echo "  Ctrl + Shift + Esc - System Monitor"
    echo "========================================="
}

# Run main function
main "$@"