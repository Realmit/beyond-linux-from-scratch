#!/bin/bash
# first-boot.sh - Exécuté une seule fois au premier démarrage
# Utilise les ressources de packages/custom-scripts/

set -e

FIRST_BOOT_FLAG="/var/lib/.first-boot-done"

if [ -f "$FIRST_BOOT_FLAG" ]; then
    exit 0
fi

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[0;34m[SUCCESS]\033[0m $1"; }
log_warning() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }

# ============================================================================
# CHARGER LA CONFIGURATION PERSONNALISÉE
# ============================================================================
CUSTOM_CONF="/packages/custom-scripts/custom-settings.conf"
if [ -f "$CUSTOM_CONF" ]; then
    source "$CUSTOM_CONF"
fi

# Variables par défaut
DEFAULT_USER="${DEFAULT_USER:-lfsuser}"
DEFAULT_PASSWORD="${DEFAULT_PASSWORD:-lfsuser123}"
HOSTNAME="${HOSTNAME:-lfs-desktop}"

# ============================================================================
# DÉTECTION DU MATÉRIEL
# ============================================================================
detect_hardware() {
    log_info "Détection du matériel..."

    CPU_VENDOR=$(lscpu | grep "Vendor ID" | cut -d: -f2 | xargs 2>/dev/null || echo "unknown")
    CPU_CORES=$(nproc 2>/dev/null || echo 1)
    RAM_GB=$(free -g | awk '/^Mem:/{print $2}' 2>/dev/null || echo 1)

    if lspci 2>/dev/null | grep -i vga | grep -qi nvidia; then
        GPU="nvidia"
    elif lspci 2>/dev/null | grep -i vga | grep -qi amd; then
        GPU="amd"
    elif lspci 2>/dev/null | grep -i vga | grep -qi intel; then
        GPU="intel"
    else
        GPU="unknown"
    fi

    cat > /etc/hardware-profile << EOF
CPU_VENDOR="$CPU_VENDOR"
CPU_CORES="$CPU_CORES"
RAM_GB="$RAM_GB"
GPU="$GPU"
HOSTNAME="$HOSTNAME"
EOF

    log_success "Matériel détecté: $GPU, $CPU_CORES cœurs, ${RAM_GB}GB RAM"
}

# ============================================================================
# CONFIGURATION RÉSEAU
# ============================================================================
configure_network() {
    log_info "Configuration réseau..."

    # Définir le hostname
    echo "$HOSTNAME" > /etc/hostname
    hostname "$HOSTNAME"

    # DHCP sur toutes les interfaces
    for iface in $(ip link show | grep -E '^[0-9]+: e' | cut -d: -f2 | xargs); do
        log_info "Configuration de $iface en DHCP..."
        dhcpcd "$iface" 2>/dev/null || dhclient "$iface" 2>/dev/null || true
    done

    # Tester la connexion
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log_success "Réseau connecté !"
    else
        log_warning "Connexion réseau échouée. Configuration manuelle nécessaire."
    fi
}

# ============================================================================
# CRÉATION DE L'UTILISATEUR
# ============================================================================
create_user() {
    log_info "Création de l'utilisateur $DEFAULT_USER..."

    if ! id "$DEFAULT_USER" &>/dev/null; then
        useradd -m -G wheel,audio,video,storage,docker,plugdev -s /bin/bash "$DEFAULT_USER"
        echo "$DEFAULT_USER:$DEFAULT_PASSWORD" | chpasswd
        echo "$DEFAULT_USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/"$DEFAULT_USER"
        log_success "Utilisateur créé"
    else
        log_info "Utilisateur existe déjà"
    fi
}

# ============================================================================
# CONFIGURATION BASH
# ============================================================================
configure_bash() {
    log_info "Configuration Bash..."

    cat >> /etc/bash.bashrc << 'BASH'
# Custom prompt
PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

# Aliases
alias ls='ls --color=auto'
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'
alias ..='cd ..'
alias ...='cd ../..'

# History
HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoreboth
HISTTIMEFORMAT="%F %T "

# PATH
export PATH="$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
BASH

    # Pour le user
    if [ -d "/home/$DEFAULT_USER" ]; then
        cp /etc/bash.bashrc "/home/$DEFAULT_USER/.bashrc"
        chown "$DEFAULT_USER:$DEFAULT_USER" "/home/$DEFAULT_USER/.bashrc"
    fi
}

# ============================================================================
# ACTIVATION DES SERVICES
# ============================================================================
enable_services() {
    log_info "Activation des services..."

    # Services système
    for svc in systemd-networkd systemd-resolved dbus; do
        systemctl enable "$svc" 2>/dev/null || true
    done

    # Bluetooth si présent
    if command -v bluetoothd >/dev/null 2>&1; then
        systemctl enable bluetooth 2>/dev/null || true
    fi

    # Cups si présent
    if command -v cupsd >/dev/null 2>&1; then
        systemctl enable cups 2>/dev/null || true
    fi

    # Gestionnaire de connexion
    if systemctl list-unit-files | grep -q lightdm; then
        systemctl enable lightdm 2>/dev/null || true
        systemctl set-default graphical.target 2>/dev/null || true
    elif systemctl list-unit-files | grep -q gdm; then
        systemctl enable gdm 2>/dev/null || true
        systemctl set-default graphical.target 2>/dev/null || true
    elif systemctl list-unit-files | grep -q sddm; then
        systemctl enable sddm 2>/dev/null || true
        systemctl set-default graphical.target 2>/dev/null || true
    fi

    log_success "Services activés"
}

# ============================================================================
# CONFIGURATION DE LA PERSISTANCE (mode live)
# ============================================================================
setup_persistence() {
    log_info "Configuration de la persistance live..."

    # Vérifier si une partition de persistance existe
    PERSIST_PART=$(blkid -L "LFS-PERSIST" 2>/dev/null)

    if [ -n "$PERSIST_PART" ]; then
        mkdir -p /mnt/persist
        mount "$PERSIST_PART" /mnt/persist 2>/dev/null || true

        if [ -d /mnt/persist ]; then
            mkdir -p /mnt/persist/{upper,work}
            # Créer un fichier de marque pour que le script live sache utiliser la persistance
            touch /var/lib/live-persistence-enabled
            log_success "Persistance live activée sur $PERSIST_PART"
        fi
    else
        log_info "Aucune partition de persistance trouvée"
    fi
}

# ============================================================================
# MESSAGE DE BIENVENUE
# ============================================================================
create_welcome() {
    log_info "Création du message de bienvenue..."

    cat > /etc/profile.d/welcome.sh << 'WELCOME'
#!/bin/bash

if [ "$PS1" ]; then
    echo "=================================================="
    echo "  Bienvenue sur LFS Linux $(cat /etc/lfs-release 2>/dev/null)"
    echo "=================================================="
    echo "  Kernel : $(uname -r)"
    echo "  CPU    : $(nproc) cœurs"
    echo "  RAM    : $(free -h | awk '/^Mem:/{print $2}')"
    echo "  Bureau : $(cat /etc/desktop-environment 2>/dev/null || echo 'inconnu')"
    echo "=================================================="
    echo ""
fi
WELCOME

    chmod +x /etc/profile.d/welcome.sh

    # Ajouter le logo du système
    if [ -f /usr/share/icons/hicolor/256x256/apps/lfs-logo.png ]; then
        echo "  Logo : LFS Linux" >> /etc/issue
    fi
}

# ============================================================================
# NETTOYAGE
# ============================================================================
cleanup() {
    log_info "Nettoyage..."

    # Supprimer les fichiers temporaires
    rm -rf /tmp/* 2>/dev/null || true
    rm -rf /var/tmp/* 2>/dev/null || true

    # Vider les logs (les plus anciens)
    find /var/log -name "*.log" -mtime +30 -delete 2>/dev/null || true

    log_success "Nettoyage terminé"
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    log_info "=== CONFIGURATION DU PREMIER DÉMARRAGE ==="

    # Vérifier les droits
    if [ "$EUID" -ne 0 ]; then
        log_warning "Le script doit être exécuté en root"
        exit 1
    fi

    detect_hardware
    configure_network
    create_user
    configure_bash
    enable_services
    setup_persistence
    create_welcome
    cleanup

    # Marquer comme terminé
    touch "$FIRST_BOOT_FLAG"

    log_success "=== SYSTÈME PRÊT ! ==="
    echo ""
    echo "=================================================="
    echo "  LFS LINUX EST MAINTENANT PRÊT À L'EMPLOI"
    echo "=================================================="
    echo "  Utilisateur : $DEFAULT_USER"
    echo "  Mot de passe : $DEFAULT_PASSWORD"
    echo ""
    echo "  N'oubliez pas de changer votre mot de passe !"
    echo "=================================================="
}

main "$@"