#!/bin/bash
# LFS/BLFS Branding Script
# Ajoute logo, thème, fonds d'écran et personnalisation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/utils.sh"

log_info "========================================="
log_info "LFS Branding and Theming"
log_info "========================================="

# ============================================================================
# CONFIGURATION
# ============================================================================

BRANDING_DIR="${BRANDING_DIR:-branding/default}"
DISTRO_NAME="${DISTRO_NAME:-LFS Linux}"
DISTRO_VERSION="${DISTRO_VERSION:-13.0}"
DISTRO_CODENAME="${DISTRO_CODENAME:-Beyond}"
DISTRO_HOMEPAGE="${DISTRO_HOMEPAGE:-https://www.linuxfromscratch.org/}"

# ============================================================================
# SYSTEM IDENTIFICATION
# ============================================================================

setup_os_release() {
    log_info "Setting up OS release information..."

    cat > /etc/os-release << EOF
NAME="$DISTRO_NAME"
VERSION="$DISTRO_VERSION ($DISTRO_CODENAME)"
ID=lfs
ID_LIKE=linux
PRETTY_NAME="$DISTRO_NAME $DISTRO_VERSION"
VERSION_ID="$DISTRO_VERSION"
HOME_URL="$DISTRO_HOMEPAGE"
SUPPORT_URL="$DISTRO_HOMEPAGE/support"
BUG_REPORT_URL="$DISTRO_HOMEPAGE/bugs"
PRIVACY_POLICY_URL="$DISTRO_HOMEPAGE/privacy"
VERSION_CODENAME="$DISTRO_CODENAME"
UBUNTU_CODENAME="$DISTRO_CODENAME"
LOGO=distributor-logo
EOF

    cat > /etc/lfs-release << EOF
$DISTRO_NAME $DISTRO_VERSION
EOF

    echo "$DISTRO_CODENAME" > /etc/lfs-codename

    log_success "OS release configured"
}

# ============================================================================
# BOOTLOADER BRANDING (GRUB)
# ============================================================================

setup_grub_branding() {
    log_info "Configuring GRUB branding..."

    # Copier le logo pour GRUB
    if [ -f "$BRANDING_DIR/logo/boot-logo.png" ]; then
        mkdir -p /boot/grub/themes/lfs
        cp "$BRANDING_DIR/logo/boot-logo.png" /boot/grub/themes/lfs/logo.png

        # Créer le thème GRUB
        cat > /boot/grub/themes/lfs/theme.txt << EOF
title-text: ""
title-font: "Unifont Regular 16"
title-color: "#FFFFFF"

message-font: "Unifont Regular 16"
message-color: "#FFFFFF"
message-bg-color: "#000000"

desktop-color: "#000000"
desktop-image: "logo.png"

terminal-box: "menu_bkg_*.png"
terminal-font: "Unifont Regular 16"
terminal-left: "0"
terminal-top: "0"
terminal-width: "100%"
terminal-height: "100%"

menu-panel-border: 0
menu-panel-border-color: "#000000"

menu-hilight-color: "#FFFFFF"
menu-hilight-bg-color: "#2E8B57"
EOF

        # Activer le thème dans GRUB
        sed -i '/GRUB_THEME=/d' /etc/default/grub
        echo "GRUB_THEME=/boot/grub/themes/lfs/theme.txt" >> /etc/default/grub
    fi

    # Ajouter le nom de la distribution
    sed -i "s/GRUB_DISTRIBUTOR=.*/GRUB_DISTRIBUTOR=\"$DISTRO_NAME\"/" /etc/default/grub

    log_success "GRUB branding configured"
}

# ============================================================================
# WALLPAPER & BACKGROUND
# ============================================================================

setup_wallpapers() {
    log_info "Installing wallpapers..."

    mkdir -p /usr/share/backgrounds/lfs

    # Copier les fonds d'écran
    if [ -f "$BRANDING_DIR/wallpaper/default.jpg" ]; then
        cp "$BRANDING_DIR/wallpaper/default.jpg" /usr/share/backgrounds/lfs/default.jpg
        ln -sf /usr/share/backgrounds/lfs/default.jpg /usr/share/backgrounds/lfs/current.jpg
    fi

    if [ -f "$BRANDING_DIR/wallpaper/login.jpg" ]; then
        cp "$BRANDING_DIR/wallpaper/login.jpg" /usr/share/backgrounds/lfs/login.jpg
    fi

    if [ -f "$BRANDING_DIR/wallpaper/grub.jpg" ]; then
        cp "$BRANDING_DIR/wallpaper/grub.jpg" /boot/grub/background.jpg
    fi

    # Créer un fichier de métadonnées
    cat > /usr/share/backgrounds/lfs/backgrounds.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE wallpapers SYSTEM "gnome-wp-list.dtd">
<wallpapers>
  <wallpaper deleted="false">
    <name>$DISTRO_NAME Default</name>
    <filename>/usr/share/backgrounds/lfs/default.jpg</filename>
    <options>zoom</options>
    <pcolor>#000000</pcolor>
    <scolor>#000000</scolor>
    <shade_type>solid</shade_type>
  </wallpaper>
</wallpapers>
EOF

    log_success "Wallpapers installed"
}

# ============================================================================
# LOGO & ICONS
# ============================================================================

setup_logos() {
    log_info "Installing logos..."

    mkdir -p /usr/share/pixmaps/lfs
    mkdir -p /usr/share/icons/hicolor/{16x16,32x32,48x48,64x64,128x128,256x256}/apps

    # Copier le logo principal
    if [ -f "$BRANDING_DIR/logo/logo.png" ]; then
        cp "$BRANDING_DIR/logo/logo.png" /usr/share/pixmaps/lfs/logo.png
        cp "$BRANDING_DIR/logo/logo.png" /usr/share/pixmaps/distributor-logo.png
    fi

    if [ -f "$BRANDING_DIR/logo/logo-white.png" ]; then
        cp "$BRANDING_DIR/logo/logo-white.png" /usr/share/pixmaps/lfs/logo-white.png
    fi

    # Créer l'icône de l'application
    if [ -f "$BRANDING_DIR/logo/logo.png" ]; then
        convert /usr/share/pixmaps/lfs/logo.png -resize 16x16 /usr/share/icons/hicolor/16x16/apps/lfs.png
        convert /usr/share/pixmaps/lfs/logo.png -resize 32x32 /usr/share/icons/hicolor/32x32/apps/lfs.png
        convert /usr/share/pixmaps/lfs/logo.png -resize 48x48 /usr/share/icons/hicolor/48x48/apps/lfs.png
        convert /usr/share/pixmaps/lfs/logo.png -resize 64x64 /usr/share/icons/hicolor/64x64/apps/lfs.png
        convert /usr/share/pixmaps/lfs/logo.png -resize 128x128 /usr/share/icons/hicolor/128x128/apps/lfs.png
        convert /usr/share/pixmaps/lfs/logo.png -resize 256x256 /usr/share/icons/hicolor/256x256/apps/lfs.png
    fi

    log_success "Logos installed"
}

# ============================================================================
# GTK THEME (LightDM, Desktop)
# ============================================================================

setup_gtk_theme() {
    log_info "Configuring GTK theme..."

    mkdir -p /usr/share/themes/LFS
    mkdir -p /usr/share/themes/LFS/gtk-3.0
    mkdir -p /usr/share/themes/LFS/gtk-4.0

    # GTK 3.0 theme
    cat > /usr/share/themes/LFS/gtk-3.0/gtk.css << 'EOF'
/* LFS Branded GTK Theme */
@define-color lfs_green #2E8B57;
@define-color lfs_dark #1a1a2e;
@define-color lfs_light #f0f0f0;

* {
    -GtkButton-default-border: 2px solid @lfs_green;
    -GtkButton-default-outside-border: 2px solid @lfs_green;
}

window {
    background-color: @lfs_dark;
    color: @lfs_light;
}

button {
    background-color: @lfs_green;
    border-radius: 6px;
    padding: 6px 12px;
}

button:hover {
    background-color: #3cb371;
}

button:active {
    background-color: #236b43;
}

entry {
    background-color: #2a2a3e;
    border: 1px solid @lfs_green;
    border-radius: 4px;
    padding: 6px;
}

menu {
    background-color: @lfs_dark;
    border: 1px solid @lfs_green;
}

menu > menuitem:hover {
    background-color: @lfs_green;
}

.notebook header {
    background-color: #1e1e2e;
}

.notebook tab {
    background-color: #252535;
    padding: 8px;
}

.notebook tab:checked {
    background-color: @lfs_green;
}

scrollbar slider {
    background-color: @lfs_green;
    border-radius: 6px;
    min-width: 6px;
    min-height: 6px;
}
EOF

    # GTK 4.0 theme (similaire)
    cp /usr/share/themes/LFS/gtk-3.0/gtk.css /usr/share/themes/LFS/gtk-4.0/

    # Créer le fichier index.theme
    cat > /usr/share/themes/LFS/index.theme << EOF
[Desktop Entry]
Name=LFS
Comment=LFS Branded Theme
Encoding=UTF-8
Type=X-GNOME-Metatheme

[GTK]
MoreSpecific=1
Default=1

[X-GNOME-Metatheme]
GtkTheme=LFS
MetacityTheme=LFS
IconTheme=Adwaita
CursorTheme=Adwaita
EOF

    # Définir comme thème par défaut
    if command -v gsettings &> /dev/null; then
        gsettings set org.gnome.desktop.interface gtk-theme "LFS" 2>/dev/null || true
    fi

    log_success "GTK theme configured"
}

# ============================================================================
# DISPLAY MANAGER BRANDING (LightDM/GDM)
# ============================================================================

setup_display_manager_branding() {
    log_info "Configuring display manager branding..."

    # LightDM configuration
    if [ -f /etc/lightdm/lightdm.conf ]; then
        mkdir -p /etc/lightdm
        mkdir -p /usr/share/lightdm-gtk-greeter

        # Logo pour LightDM
        if [ -f "$BRANDING_DIR/logo/logo.png" ]; then
            cp "$BRANDING_DIR/logo/logo.png" /usr/share/lightdm-gtk-greeter/logo.png
        fi

        # Fond d'écran LightDM
        if [ -f "$BRANDING_DIR/wallpaper/login.jpg" ]; then
            cp "$BRANDING_DIR/wallpaper/login.jpg" /usr/share/lightdm-gtk-greeter/background.jpg
        fi

        cat > /etc/lightdm/lightdm-gtk-greeter.conf << EOF
[greeter]
background=/usr/share/lightdm-gtk-greeter/background.jpg
logo=/usr/share/lightdm-gtk-greeter/logo.png
theme-name=LFS
icon-theme-name=Adwaita
font-name=Noto Sans 10
xft-antialias=true
xft-dpi=96
screensaver-timeout=60
indicators=~host;~spacer;~clock;~power
EOF
    fi

    # GDM configuration
    if [ -f /etc/gdm/custom.conf ]; then
        mkdir -p /etc/gdm
        cat > /etc/gdm/custom.conf << EOF
[daemon]
# GDM configuration for $DISTRO_NAME
AutomaticLoginEnable=false

[security]

[xdmcp]

[chooser]

[debug]
EOF
    fi

    log_success "Display manager branding configured"
}

# ============================================================================
# DESKTOP ENVIRONMENT BRANDING (XFCE/GNOME/KDE)
# ============================================================================

setup_desktop_branding() {
    log_info "Configuring desktop environment branding..."

    # XFCE configuration
    if command -v xfce4-session &> /dev/null; then
        mkdir -p /etc/xdg/xfce4/xfconf/xfce-perchannel-xml

        # Fond d'écran XFCE
        if [ -f "$BRANDING_DIR/wallpaper/default.jpg" ]; then
            cat > /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitor0" type="empty">
        <property name="image-path" type="string" value="/usr/share/backgrounds/lfs/default.jpg"/>
        <property name="image-style" type="int" value="5"/>
      </property>
    </property>
  </property>
</channel>
EOF
        fi
    fi

    log_success "Desktop branding configured"
}

# ============================================================================
# PLYMOUTH BOOT SPLASH (Themed boot)
# ============================================================================

setup_plymouth() {
    log_info "Configuring Plymouth boot splash..."

    if command -v plymouth-set-default-theme &> /dev/null; then
        mkdir -p /usr/share/plymouth/themes/lfs

        # Logo pour Plymouth
        if [ -f "$BRANDING_DIR/logo/logo.png" ]; then
            cp "$BRANDING_DIR/logo/logo.png" /usr/share/plymouth/themes/lfs/logo.png
        fi

        # Configuration Plymouth
        cat > /usr/share/plymouth/themes/lfs/lfs.plymouth << EOF
[Plymouth Theme]
Name=LFS
Description=LFS Branded Boot Splash
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/lfs
ScriptFile=/usr/share/plymouth/themes/lfs/lfs.script
EOF

        # Script de thème
        cat > /usr/share/plymouth/themes/lfs/lfs.script << 'EOF'
# LFS Plymouth Theme
wallpaper_image = Image("/usr/share/plymouth/themes/lfs/logo.png");
logo_image = Image("/usr/share/plymouth/themes/lfs/logo.png");

fun refresh_callback () {
    wallpaper_image = Image("/usr/share/plymouth/themes/lfs/logo.png");
    logo_image = Image("/usr/share/plymouth/themes/lfs/logo.png");
}

# Afficher le logo
logo_sprite = Sprite(logo_image);
logo_sprite.SetX(Window.GetWidth()/2 - logo_image.GetWidth()/2);
logo_sprite.SetY(Window.GetHeight()/2 - logo_image.GetHeight()/2);
logo_sprite.SetOpacity(1.0);
EOF

        # Définir comme thème par défaut
        plymouth-set-default-theme lfs
    fi

    log_success "Plymouth configured"
}

# ============================================================================
# INSTALLER BRANDING
# ============================================================================

setup_installer_branding() {
    log_info "Configuring installer branding..."

    mkdir -p /etc/lfs-installer

    # Message d'accueil
    cat > /etc/lfs-installer/welcome.txt << EOF
╔═══════════════════════════════════════════════════════════════════════════╗
║                                                                           ║
║                    Welcome to $DISTRO_NAME $DISTRO_VERSION                ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝

This installer will guide you through the installation of $DISTRO_NAME.

Features:
  • Complete Linux system from scratch
  • Your choice of desktop environment
  • Security hardened by default
  • Live system to try before installing

For help: https://www.linuxfromscratch.org/
EOF

    log_success "Installer branding configured"
}

# ============================================================================
# MOTD & SHELL PROMPT
# ============================================================================

setup_motd() {
    log_info "Configuring Message of the Day..."

    cat > /etc/motd << EOF
╔═══════════════════════════════════════════════════════════════════════════╗
║                                                                           ║
║   $DISTRO_NAME $DISTRO_VERSION ($DISTRO_CODENAME)                         ║
║   Built from Linux From Scratch (LFS) $DISTRO_VERSION                     ║
║                                                                           ║
║   Type 'help' for available commands                                      ║
║   Documentation: man LFS                                                  ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝
EOF

    # Personnaliser le prompt
    cat >> /etc/bash.bashrc << 'EOF'

# LFS Branded Prompt
if [ "$PS1" ]; then
    PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

    # Ajouter une couleur verte pour l'utilisateur root
    if [ $EUID -eq 0 ]; then
        PS1='\[\033[01;31m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]# '
    fi
fi
EOF

    log_success "MOTD configured"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    setup_os_release
    setup_grub_branding
    setup_wallpapers
    setup_logos
    setup_gtk_theme
    setup_display_manager_branding
    setup_desktop_branding
    setup_plymouth
    setup_installer_branding
    setup_motd

    log_success "========================================="
    log_success "Branding and Theming Complete!"
    log_success "========================================="
}

main "$@"