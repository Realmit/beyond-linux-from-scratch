#!/bin/bash
# GNOME Desktop Profile for LFS
# Complete GNOME 45 desktop environment setup

set -e

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[0;34m[SUCCESS]\033[0m $1"; }
log_warning() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

# ============================================================================
# GNOME SPECIFIC CONFIGURATION
# ============================================================================

GNOME_VERSION="45"
NUM_JOBS=${NUM_JOBS:-$(nproc)}
PACKAGE_LIST="profiles/gnome/packages.list"

# ============================================================================
# PREREQUISITES CHECK
# ============================================================================
check_prerequisites() {
    log_info "Checking GNOME build prerequisites..."

    # Check for meson and ninja
    if ! command -v meson &> /dev/null; then
        log_error "meson not found. Installing..."
        pip3 install meson
    fi

    if ! command -v ninja &> /dev/null; then
        log_error "ninja not found. Installing..."
        apt-get install -y ninja-build 2>/dev/null || yum install -y ninja-build 2>/dev/null
    fi

    log_success "Prerequisites satisfied"
}

# ============================================================================
# BUILD CORE DEPENDENCIES
# ============================================================================
build_core_dependencies() {
    log_info "Building core GNOME dependencies..."

    cd /sources

    # gtk-doc (documentation generator)
    if [ -f "gtk-doc-*.tar.xz" ]; then
        log_info "Building gtk-doc..."
        tar -xf gtk-doc-*.tar.xz
        cd gtk-doc-*
        meson setup --prefix=/usr --buildtype=release build
        ninja -C build
        ninja -C build install
        cd ..
    fi

    # libxml2
    if [ -f "libxml2-*.tar.xz" ]; then
        log_info "Building libxml2..."
        tar -xf libxml2-*.tar.xz
        cd libxml2-*
        ./configure --prefix=/usr --disable-static --with-history
        make -j$NUM_JOBS
        make install
        cd ..
    fi

    # gobject-introspection
    if [ -f "gobject-introspection-*.tar.xz" ]; then
        log_info "Building gobject-introspection..."
        tar -xf gobject-introspection-*.tar.xz
        cd gobject-introspection-*
        meson setup --prefix=/usr --buildtype=release build
        ninja -C build
        ninja -C build install
        cd ..
    fi

    # GLib (if not already installed)
    if [ -f "glib-*.tar.xz" ]; then
        log_info "Building GLib..."
        tar -xf glib-*.tar.xz
        cd glib-*
        meson setup --prefix=/usr --buildtype=release -Dgtk_doc=false build
        ninja -C build
        ninja -C build install
        cd ..
    fi

    log_success "Core dependencies built"
}

# ============================================================================
# BUILD GTK4 (Required for GNOME 45)
# ============================================================================
build_gtk4() {
    log_info "Building GTK4..."

    cd /sources

    if [ -f "gtk-*.tar.xz" ]; then
        tar -xf gtk-*.tar.xz
        cd gtk-*

        # Configure with meson
        meson setup --prefix=/usr \
                    --buildtype=release \
                    -Dbroadway_backend=true \
                    -Dvulkan=enabled \
                    -Dwayland-backend=true \
                    -Dx11-backend=true \
                    build

        ninja -C build
        ninja -C build install

        cd ..
    fi

    log_success "GTK4 built"
}

# ============================================================================
# BUILD LIBADWAITA (Adwaita widgets for GTK4)
# ============================================================================
build_libadwaita() {
    log_info "Building libadwaita..."

    cd /sources

    if [ -f "libadwaita-*.tar.xz" ]; then
        tar -xf libadwaita-*.tar.xz
        cd libadwaita-*

        meson setup --prefix=/usr --buildtype=release build
        ninja -C build
        ninja -C build install

        cd ..
    fi

    log_success "libadwaita built"
}

# ============================================================================
# BUILD GNOME SHELL
# ============================================================================
build_gnome_shell() {
    log_info "Building GNOME Shell... (this will take a while)"

    cd /sources

    # mutter (window manager for GNOME)
    if [ -f "mutter-*.tar.xz" ]; then
        log_info "Building mutter..."
        tar -xf mutter-*.tar.xz
        cd mutter-*

        meson setup --prefix=/usr \
                    --buildtype=release \
                    -Dudev=true \
                    -Dwayland=true \
                    -Dx11=true \
                    build

        ninja -C build
        ninja -C build install
        cd ..
    fi

    # gnome-shell
    if [ -f "gnome-shell-*.tar.xz" ]; then
        log_info "Building gnome-shell..."
        tar -xf gnome-shell-*.tar.xz
        cd gnome-shell-*

        meson setup --prefix=/usr \
                    --buildtype=release \
                    -Dextensions_app=true \
                    build

        ninja -C build
        ninja -C build install
        cd ..
    fi

    log_success "GNOME Shell built"
}

# ============================================================================
# BUILD GNOME CORE COMPONENTS
# ============================================================================
build_gnome_core() {
    log_info "Building GNOME core components..."

    cd /sources

    # List of core GNOME components
    local components=(
        "gnome-desktop"
        "gnome-session"
        "gnome-control-center"
        "gnome-settings-daemon"
        "nautilus"
        "gnome-terminal"
        "gnome-system-monitor"
        "gnome-calculator"
        "gnome-calendar"
        "gnome-logs"
        "gnome-disk-utility"
    )

    for component in "${components[@]}"; do
        if [ -f "${component}-*.tar.xz" ]; then
            log_info "Building $component..."
            tar -xf ${component}-*.tar.xz
            cd ${component}-*

            # Most GNOME components use meson now
            if [ -f "meson.build" ]; then
                meson setup --prefix=/usr --buildtype=release build
                ninja -C build
                ninja -C build install
            elif [ -f "configure" ]; then
                ./configure --prefix=/usr
                make -j$NUM_JOBS
                make install
            fi

            cd ..
        fi
    done

    log_success "GNOME core components built"
}

# ============================================================================
# BUILD GNOME APPLICATIONS
# ============================================================================
build_gnome_apps() {
    log_info "Building GNOME applications..."

    cd /sources

    local applications=(
        "epiphany"      # Web browser
        "evince"        # Document viewer
        "eog"           # Image viewer
        "totem"         # Video player
        "gedit"         # Text editor
        "file-roller"   # Archive manager
        "baobab"        # Disk usage analyzer
        "gnome-software" # Software center
    )

    for app in "${applications[@]}"; do
        if [ -f "${app}-*.tar.xz" ]; then
            log_info "Building $app..."
            tar -xf ${app}-*.tar.xz
            cd ${app}-*

            if [ -f "meson.build" ]; then
                meson setup --prefix=/usr --buildtype=release build
                ninja -C build
                ninja -C build install
            elif [ -f "configure" ]; then
                ./configure --prefix=/usr
                make -j$NUM_JOBS
                make install
            fi

            cd ..
        fi
    done

    log_success "GNOME applications built"
}

# ============================================================================
# CONFIGURE GDM (GNOME Display Manager)
# ============================================================================
configure_gdm() {
    log_info "Configuring GDM..."

    # Create GDM configuration directory
    mkdir -p /etc/gdm

    # Main GDM configuration
    cat > /etc/gdm/custom.conf << 'EOF'
[daemon]
# Automatic login
AutomaticLoginEnable=True
AutomaticLogin=lfsuser

# Wayland by default (fallback to X11 if needed)
# WaylandEnable=True
DefaultSession=gnome-wayland

[security]
# Disallow root login via GDM
AllowRoot=false

[xdmcp]
# Disable remote login
Enable=false

[chooser]
# Disable chooser
Multicast=false

[debug]
# Enable debug logging (disable for production)
# Enable=true
EOF

    # Configure GDM as default display manager
    if command -v systemctl &> /dev/null; then
        systemctl enable gdm
        systemctl set-default graphical.target
    fi

    # Create GDM session file
    mkdir -p /usr/share/xsessions
    cat > /usr/share/xsessions/gnome.desktop << 'EOF'
[Desktop Entry]
Name=GNOME
Comment=This session logs you into GNOME
Exec=gnome-session
TryExec=gnome-session
Type=Application
DesktopNames=GNOME
X-GDM-SessionRegisters=true
EOF

    # Wayland session
    mkdir -p /usr/share/wayland-sessions
    cat > /usr/share/wayland-sessions/gnome-wayland.desktop << 'EOF'
[Desktop Entry]
Name=GNOME on Wayland
Comment=This session logs you into GNOME using Wayland
Exec=gnome-session
TryExec=gnome-session
Type=Application
DesktopNames=GNOME
X-GDM-SessionRegisters=true
EOF

    log_success "GDM configured"
}

# ============================================================================
# CONFIGURE GNOME SETTINGS
# ============================================================================
configure_gnome_settings() {
    log_info "Configuring GNOME settings..."

    # Create dconf database with default settings
    mkdir -p /etc/dconf/db/local.d

    cat > /etc/dconf/db/local.d/00-default-settings << 'EOF'
# Default GNOME settings for all users

[org/gnome/desktop/interface]
gtk-theme='Adwaita'
icon-theme='Adwaita'
font-name='Cantarell 11'
document-font-name='Cantarell 11'
monospace-font-name='Source Code Pro 11'
clock-format='12h'
clock-show-date=true
clock-show-weekday=true
enable-hot-corners=false

[org/gnome/desktop/wm/preferences]
button-layout='appmenu:minimize,maximize,close'
theme='Adwaita'

[org/gnome/desktop/privacy]
remember-recent-files=true
remove-old-temp-files=true
old-files-age=30

[org/gnome/desktop/search-providers]
disable-external=true

[org/gnome/desktop/background]
picture-uri='file:///usr/share/backgrounds/gnome/adwaita-day.jpg'
picture-uri-dark='file:///usr/share/backgrounds/gnome/adwaita-night.jpg'

[org/gnome/desktop/screensaver]
lock-enabled=true
lock-delay=uint32 300

[org/gnome/shell]
enabled-extensions=[]
favorite-apps=['firefox.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Terminal.desktop', 'libreoffice-writer.desktop']

[org/gnome/terminal/legacy]
default-show-menubar=false
theme-variant='dark'

[org/gnome/nautilus/preferences]
default-folder-viewer='list-view'
show-hidden-files=false
click-policy='double'
EOF

    # Compile dconf database
    if command -v dconf &> /dev/null; then
        dconf update
    fi

    # Copy to skel for new users
    mkdir -p /etc/skel/.config/gtk-3.0
    cat > /etc/skel/.config/gtk-3.0/settings.ini << 'EOF'
[Settings]
gtk-theme-name=Adwaita
gtk-icon-theme-name=Adwaita
gtk-font-name=Cantarell 11
gtk-cursor-theme-name=Adwaita
EOF

    mkdir -p /etc/skel/.config/gtk-4.0
    cp /etc/skel/.config/gtk-3.0/settings.ini /etc/skel/.config/gtk-4.0/settings.ini

    log_success "GNOME settings configured"
}

# ============================================================================
# INSTALL GNOME EXTENSIONS
# ============================================================================
install_gnome_extensions() {
    log_info "Installing GNOME extensions..."

    cd /sources

    # Dash to Dock extension
    if [ ! -d "dash-to-dock" ]; then
        git clone https://github.com/micheleg/dash-to-dock.git
        cd dash-to-dock
        make install
        cd ..
    fi

    # User Themes extension
    if [ ! -d "user-themes" ]; then
        git clone https://github.com/charlesg99/gnome-shell-extension-user-themes.git user-themes
        cd user-themes
        make install
        cd ..
    fi

    # Clipboard Indicator
    if [ ! -d "clipboard-indicator" ]; then
        git clone https://github.com/Tudmotu/gnome-shell-extension-clipboard-indicator.git clipboard-indicator
        cd clipboard-indicator
        make install
        cd ..
    fi

    # Enable extensions
    cat > /etc/dconf/db/local.d/01-extensions << 'EOF'
[org/gnome/shell]
enabled-extensions=['dash-to-dock@micxgx.gmail.com', 'user-theme@gnome-shell-extensions.gcampax.github.com', 'clipboard-indicator@tudmotu.com']
EOF

    dconf update 2>/dev/null || true

    log_success "GNOME extensions installed"
}

# ============================================================================
# CONFIGURE KEYRING AND PAM
# ============================================================================
configure_keyring() {
    log_info "Configuring GNOME Keyring..."

    # Install PAM configuration for keyring
    if [ -f /etc/pam.d/login ]; then
        if ! grep -q "pam_gnome_keyring.so" /etc/pam.d/login; then
            sed -i '/auth.*required.*pam_securetty.so/a auth    optional    pam_gnome_keyring.so' /etc/pam.d/login
            sed -i '/session.*required.*pam_unix.so/a session optional    pam_gnome_keyring.so auto_start' /etc/pam.d/login
        fi
    fi

    # Create keyring directory
    mkdir -p /etc/skel/.local/share/keyrings

    log_success "GNOME Keyring configured"
}

# ============================================================================
# SETUP GNOME BACKGROUNDS
# ============================================================================
setup_backgrounds() {
    log_info "Setting up GNOME backgrounds..."

    mkdir -p /usr/share/backgrounds/gnome

    # Download default GNOME 45 wallpaper if not exists
    cd /usr/share/backgrounds/gnome
    if [ ! -f "adwaita-day.jpg" ]; then
        wget -q https://raw.githubusercontent.com/gnome/gnome-backgrounds/main/backgrounds/adwaita-day.jpg 2>/dev/null || true
        wget -q https://raw.githubusercontent.com/gnome/gnome-backgrounds/main/backgrounds/adwaita-night.jpg 2>/dev/null || true
    fi

    log_success "Backgrounds configured"
}

# ============================================================================
# CLEANUP
# ============================================================================
cleanup() {
    log_info "Cleaning up temporary files..."

    cd /sources
    rm -rf gtk-doc-* libxml2-* gobject-introspection-* glib-* gtk-* libadwaita-*
    rm -rf mutter-* gnome-shell-* gnome-desktop-* gnome-session-* gnome-control-center-*
    rm -rf nautilus-* gnome-terminal-* epiphany-* evince-* eog-* totem-* gedit-*

    log_success "Cleanup complete"
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    log_info "========================================="
    log_info "GNOME Desktop Installation"
    log_info "========================================="
    log_warning "This will take several hours..."
    echo ""

    check_prerequisites
    build_core_dependencies
    build_gtk4
    build_libadwaita
    build_gnome_shell
    build_gnome_core
    build_gnome_apps
    configure_gdm
    configure_gnome_settings
    install_gnome_extensions
    configure_keyring
    setup_backgrounds
    cleanup

    log_success "========================================="
    log_success "GNOME Desktop Installation Complete!"
    log_success "========================================="
    echo ""
    echo "GNOME $GNOME_VERSION has been installed successfully."
    echo ""
    echo "To start GNOME:"
    echo "  1. Reboot your system"
    echo "  2. Login with your user account"
    echo "  3. GNOME will start automatically"
    echo ""
    echo "If GNOME doesn't start automatically:"
    echo "  startx /usr/bin/gnome-session"
    echo ""
    echo "Default login: lfsuser / lfsuser123"
    echo "========================================="
}

# Run main function
main "$@"