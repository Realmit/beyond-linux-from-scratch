#!/bin/bash
# theme-setup.sh - Applique le thème et les personnalisations
# Utilise les ressources de packages/custom-scripts/

set -e

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[0;34m[SUCCESS]\033[0m $1"; }

# ============================================================================
# VARIABLES (surchargeables via l'environnement ou un fichier .conf)
# ============================================================================
THEME_NAME="${THEME_NAME:-Arc-Dark}"
ICON_THEME="${ICON_THEME:-Papirus}"
FONT_NAME="${FONT_NAME:-Noto Sans 10}"
DESKTOP_TYPE="${DESKTOP_TYPE:-xfce}"

# Chemins des ressources personnalisées
CUSTOM_DIR="/packages/custom-scripts"
WALLPAPER_SRC="${CUSTOM_DIR}/wallpaper.jpg"
LOGO_SRC="${CUSTOM_DIR}/logo.png"
CUSTOM_CONF="${CUSTOM_DIR}/custom-settings.conf"

# Dossiers système
TARGET_WALLPAPER="/usr/share/backgrounds/default.jpg"
TARGET_LOGO="/usr/share/icons/hicolor/256x256/apps/lfs-logo.png"
TARGET_CONFIG_DIR="/etc/skel/.config"

# ============================================================================
# CHARGER LA CONFIGURATION PERSONNALISÉE
# ============================================================================
if [ -f "$CUSTOM_CONF" ]; then
    log_info "Chargement de la configuration personnalisée..."
    source "$CUSTOM_CONF"
fi

# ============================================================================
# INSTALLER LES FONTS
# ============================================================================
install_fonts() {
    log_info "Installation des fonts..."

    mkdir -p /usr/share/fonts/{TTF,OTF,Type1}

    cd /sources

    # Cascadia Code (Nerd Font)
    if [ ! -f CascadiaCode.zip ]; then
        wget -q https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/CascadiaCode.zip
    fi
    unzip -qo CascadiaCode.zip -d /usr/share/fonts/TTF/

    # Noto Sans
    if [ ! -f NotoSans-hinted.zip ]; then
        wget -q https://noto-website-2.storage.googleapis.com/pkgs/NotoSans-hinted.zip
    fi
    unzip -qo NotoSans-hinted.zip -d /usr/share/fonts/TTF/

    fc-cache -fv > /dev/null 2>&1

    log_success "Fonts installées"
}

# ============================================================================
# INSTALLER LES THÈMES D'ICÔNES
# ============================================================================
install_icon_themes() {
    log_info "Installation des thèmes d'icônes..."

    cd /sources

    # Papirus
    if [ ! -f Papirus-20231201.tar.gz ]; then
        wget -q https://github.com/PapirusDevelopmentTeam/papirus-icon-theme/archive/20231201/Papirus-20231201.tar.gz
    fi
    tar -xzf Papirus-20231201.tar.gz
    cd papirus-icon-theme-20231201
    ./install.sh > /dev/null 2>&1
    cd ..

    log_success "Thèmes d'icônes installés"
}

# ============================================================================
# INSTALLER LES THÈMES GTK
# ============================================================================
install_gtk_themes() {
    log_info "Installation des thèmes GTK..."

    cd /sources

    # Arc Theme
    if [ ! -f arc-theme-20221218.tar.gz ]; then
        wget -q https://github.com/jnsh/arc-theme/archive/refs/tags/20221218.tar.gz -O arc-theme-20221218.tar.gz
    fi
    tar -xzf arc-theme-20221218.tar.gz
    cd arc-theme-20221218
    ./autogen.sh --prefix=/usr > /dev/null 2>&1
    make -j$(nproc) > /dev/null 2>&1
    make install > /dev/null 2>&1
    cd ..

    # Matcha (optionnel)
    if [ ! -f Matcha-2023-10-01.tar.gz ]; then
        wget -q https://github.com/vinceliuice/Matcha-theme/archive/2023-10-01.tar.gz -O Matcha-2023-10-01.tar.gz
    fi
    tar -xzf Matcha-2023-10-01.tar.gz
    cd Matcha-theme-2023-10-01
    ./install.sh > /dev/null 2>&1
    cd ..

    log_success "Thèmes GTK installés"
}

# ============================================================================
# COPIER LES RESSOURCES PERSONNALISÉES
# ============================================================================
install_custom_resources() {
    log_info "Installation des ressources personnalisées..."

    # Fond d'écran
    if [ -f "$WALLPAPER_SRC" ]; then
        install -Dm644 "$WALLPAPER_SRC" "$TARGET_WALLPAPER"
        log_success "Fond d'écran installé"
    else
        log_info "Aucun fond d'écran personnalisé trouvé, utilisation du défaut"
        # Télécharger un fond d'écran par défaut si le fichier n'existe pas
        mkdir -p /usr/share/backgrounds
        cd /usr/share/backgrounds
        if [ ! -f default.jpg ]; then
            wget -q -O default.jpg https://images.pexels.com/photos/147411/italy-mountains-dawn-daybreak-147411.jpeg
        fi
    fi

    # Logo
    if [ -f "$LOGO_SRC" ]; then
        install -Dm644 "$LOGO_SRC" "$TARGET_LOGO"
        # Créer les liens symboliques pour les autres tailles
        for size in 48 64 128; do
            mkdir -p "/usr/share/icons/hicolor/${size}x${size}/apps/"
            cp "$TARGET_LOGO" "/usr/share/icons/hicolor/${size}x${size}/apps/lfs-logo.png"
        done
        log_success "Logo installé"
    fi

    # Fichier de configuration personnalisée
    if [ -f "$CUSTOM_CONF" ]; then
        install -Dm644 "$CUSTOM_CONF" /etc/lfs-custom.conf
        log_success "Configuration personnalisée installée"
    fi
}

# ============================================================================
# CONFIGURER LE THÈME GTK
# ============================================================================
configure_gtk() {
    log_info "Configuration GTK..."

    # GTK 2
    mkdir -p /etc/gtk-2.0
    cat > /etc/gtk-2.0/gtkrc << EOF
gtk-theme-name="$THEME_NAME"
gtk-icon-theme-name="$ICON_THEME"
gtk-font-name="$FONT_NAME"
gtk-toolbar-style=GTK_TOOLBAR_ICONS
gtk-enable-event-sounds=0
gtk-enable-input-feedback-sounds=0
EOF

    # GTK 3 & 4
    for gtk_ver in 3.0 4.0; do
        mkdir -p "/etc/gtk-$gtk_ver"
        cat > "/etc/gtk-$gtk_ver/settings.ini" << EOF
[Settings]
gtk-theme-name=$THEME_NAME
gtk-icon-theme-name=$ICON_THEME
gtk-font-name=$FONT_NAME
gtk-cursor-theme-name=Adwaita
gtk-toolbar-style=GTK_TOOLBAR_BOTH_HORIZ
gtk-xft-antialias=1
gtk-xft-hinting=1
gtk-xft-hintstyle=hintfull
gtk-xft-rgba=rgb
EOF
    done

    # Config pour le user root
    mkdir -p /root/.config/gtk-3.0
    cp /etc/gtk-3.0/settings.ini /root/.config/gtk-3.0/

    # Config pour les nouveaux utilisateurs (skel)
    mkdir -p /etc/skel/.config/gtk-3.0
    cp /etc/gtk-3.0/settings.ini /etc/skel/.config/gtk-3.0/

    log_success "GTK configuré"
}

# ============================================================================
# CONFIGURER LE BUREAU SPÉCIFIQUE
# ============================================================================
configure_desktop() {
    log_info "Configuration du bureau $DESKTOP_TYPE..."

    case "$DESKTOP_TYPE" in
        xfce|xfce4)
            mkdir -p /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/

            # Fond d'écran XFCE
            cat > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitor0" type="empty">
        <property name="workspace0" type="empty">
          <property name="last-image" type="string" value="$TARGET_WALLPAPER"/>
          <property name="image-style" type="int" value="5"/>
          <property name="image-show" type="bool" value="true"/>
        </property>
      </property>
    </property>
  </property>
</channel>
EOF

            # Thème XFWM
            cat > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="$THEME_NAME"/>
    <property name="title_font" type="string" value="$FONT_NAME"/>
  </property>
</channel>
EOF
            ;;

        gnome)
            # GNOME utilise dconf
            if command -v dconf >/dev/null 2>&1; then
                dconf write /org/gnome/desktop/background/picture-uri "'file://$TARGET_WALLPAPER'"
                dconf write /org/gnome/desktop/background/picture-uri-dark "'file://$TARGET_WALLPAPER'"
                dconf write /org/gnome/desktop/interface/gtk-theme "'$THEME_NAME'"
                dconf write /org/gnome/desktop/interface/icon-theme "'$ICON_THEME'"
                dconf write /org/gnome/desktop/interface/font-name "'$FONT_NAME'"
            fi
            ;;

        kde)
            # KDE utilise kconfupdate ou fichiers .plasma
            if command -v plasmashell >/dev/null 2>&1; then
                cat > /etc/skel/.config/kdeglobals << EOF
[General]
ColorScheme=BreezeDark
Name=$THEME_NAME
IconTheme=$ICON_THEME
font=$FONT_NAME
EOF
            fi
            ;;

        *)
            log_info "Bureau $DESKTOP_TYPE non pris en charge pour la configuration automatique"
            ;;
    esac

    log_success "Bureau configuré"
}

# ============================================================================
# CONFIGURER LE GESTIONNAIRE DE CONNEXION
# ============================================================================
configure_display_manager() {
    log_info "Configuration du gestionnaire de connexion..."

    # LightDM
    if command -v lightdm >/dev/null 2>&1; then
        cat > /etc/lightdm/lightdm-gtk-greeter.conf << EOF
[greeter]
theme-name=$THEME_NAME
icon-theme-name=$ICON_THEME
font-name=$FONT_NAME
background=$TARGET_WALLPAPER
logo=$TARGET_LOGO
EOF
        log_success "LightDM configuré"
    fi

    # SDDM
    if command -v sddm >/dev/null 2>&1; then
        cat > /etc/sddm.conf << EOF
[Theme]
Current=breeze
CursorTheme=Adwaita
Font=$FONT_NAME
EOF
        log_success "SDDM configuré"
    fi
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    log_info "=== DÉBUT DE LA CONFIGURATION DU THÈME ==="

    install_fonts
    install_icon_themes
    install_gtk_themes
    install_custom_resources
    configure_gtk
    configure_desktop
    configure_display_manager

    # Appliquer au user lfsuser existant
    if [ -d /home/lfsuser ]; then
        cp -r /etc/skel/.config/* /home/lfsuser/.config/ 2>/dev/null || true
        chown -R lfsuser:lfsuser /home/lfsuser/.config 2>/dev/null || true
    fi

    log_success "=== CONFIGURATION DU THÈME TERMINÉE ==="
}

main "$@"