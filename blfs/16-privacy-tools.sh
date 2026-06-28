#!/bin/bash
# blfs/16-privacy-tools.sh
# Installation des outils de confidentialité pour LFS/BLFS (profil gnu-free)

set -e

log_info()  { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_success(){ echo -e "\033[0;34m[SUCCESS]\033[0m $1"; }
log_error()  { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

# Répertoires
SOURCES_DIR="/sources"
INSTALL_DIR="/usr/local"
WORK_DIR="/tmp/privacy-build"

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# ============================================================================
# FONCTIONS UTILITAIRES
# ============================================================================
download_and_extract() {
    local url="$1"
    local filename="${url##*/}"
    if [ ! -f "$SOURCES_DIR/$filename" ]; then
        log_info "Téléchargement de $filename..."
        wget -q "$url" -O "$SOURCES_DIR/$filename"
    fi
    tar -xf "$SOURCES_DIR/$filename"
}

# ============================================================================
# 1. TOR
# ============================================================================
install_tor() {
    log_info "Installation de Tor..."
    cd "$WORK_DIR"
    download_and_extract "https://dist.torproject.org/tor-0.4.8.13.tar.gz"
    cd tor-0.4.8.13
    ./configure --prefix="$INSTALL_DIR" \
        --sysconfdir=/etc \
        --localstatedir=/var \
        --disable-system-torrc
    make -j$(nproc)
    make install
    # Création d'un utilisateur dédié
    groupadd -r tor 2>/dev/null || true
    useradd -r -g tor -d /var/lib/tor tor 2>/dev/null || true
    mkdir -p /var/lib/tor /var/log/tor
    chown -R tor:tor /var/lib/tor /var/log/tor
    chmod 700 /var/lib/tor
    # Configuration minimale
    cat > /etc/tor/torrc << 'EOF'
# Configuration Tor minimale
DataDirectory /var/lib/tor
Log notice file /var/log/tor/notices.log
SocksPort 9050
ControlPort 9051
EOF
    log_success "Tor installé"
}

# ============================================================================
# 2. WIREGUARD-TOOLS
# ============================================================================
install_wireguard() {
    log_info "Installation de WireGuard-tools..."
    cd "$WORK_DIR"
    download_and_extract "https://git.zx2c4.com/wireguard-tools/snapshot/wireguard-tools-1.0.20210914.tar.xz"
    cd wireguard-tools-1.0.20210914/src
    make -j$(nproc)
    make install
    log_success "WireGuard-tools installés"
}

# ============================================================================
# 3. DNSCRYPT-PROXY
# ============================================================================
install_dnscrypt() {
    log_info "Installation de DNSCrypt-proxy..."
    cd "$WORK_DIR"
    download_and_extract "https://github.com/DNSCrypt/dnscrypt-proxy/releases/download/2.1.7/dnscrypt-proxy-2.1.7.tar.gz"
    cd dnscrypt-proxy-2.1.7
    make -j$(nproc)
    make install
    mkdir -p /etc/dnscrypt-proxy
    cp example-dnscrypt-proxy.toml /etc/dnscrypt-proxy/dnscrypt-proxy.toml
    # Créer un utilisateur
    groupadd -r dnscrypt 2>/dev/null || true
    useradd -r -g dnscrypt -d /var/empty dnscrypt 2>/dev/null || true
    log_success "DNSCrypt-proxy installé"
}

# ============================================================================
# 4. I2P (version all-in-one)
# ============================================================================
install_i2p() {
    log_info "Installation de I2P (version Java)..."
    cd "$WORK_DIR"
    # Télécharger le client Java I2P (dépend de Java)
    if command -v java >/dev/null 2>&1; then
        wget -q "https://download.i2p2.de/releases/2.7.0/i2pinstall_2.7.0.jar" -O i2pinstall.jar
        java -jar i2pinstall.jar -console <<< $'yes\n/opt/i2p'
        # Ajouter un utilisateur
        groupadd -r i2psvc 2>/dev/null || true
        useradd -r -g i2psvc -d /opt/i2p i2psvc 2>/dev/null || true
        chown -R i2psvc:i2psvc /opt/i2p
        log_success "I2P installé"
    else
        log_info "Java non trouvé, saut d'I2P"
    fi
}

# ============================================================================
# 5. MAT2 (métadata anonymizer) – dépend de Python
# ============================================================================
install_mat2() {
    log_info "Installation de Mat2..."
    cd "$WORK_DIR"
    if command -v python3 >/dev/null 2>&1; then
        download_and_extract "https://0xacab.org/jvoisin/mat2/-/archive/0.13.4/mat2-0.13.4.tar.gz"
        cd mat2-0.13.4
        python3 setup.py install
        log_success "Mat2 installé"
    else
        log_info "Python3 non trouvé, saut de Mat2"
    fi
}

# ============================================================================
# 6. HARDENING (désactivation de services, restrictions)
# ============================================================================
apply_hardening() {
    log_info "Application du durcissement privacy..."

    # Désactiver les services de localisation (si présents)
    systemctl mask geoclue 2>/dev/null || true

    # Restreindre les permissions des logs
    chmod 640 /var/log/* 2>/dev/null || true

    # Désactiver le core dumps
    echo "* hard core 0" >> /etc/security/limits.conf

    # Désactiver la télémetrie (exemple pour systemd)
    echo "EnableMetrics=no" >> /etc/systemd/system.conf
    echo "EnableMetrics=no" >> /etc/systemd/user.conf

    log_success "Durcissement appliqué"
}

# ============================================================================
# 7. NETWORK FIREWALL (nftables)
# ============================================================================
setup_firewall() {
    log_info "Configuration du pare-feu basique..."
    # Simple règles nftables pour bloquer les ports non nécessaires
    if command -v nft >/dev/null 2>&1; then
        nft add table inet filter
        nft add chain inet filter input { type filter hook input priority 0\; }
        nft add rule inet filter input ct state established,related accept
        nft add rule inet filter input iif lo accept
        nft add rule inet filter input drop
        # Sauvegarder la configuration (pour systemd-nftables)
        nft list ruleset > /etc/nftables.conf
        systemctl enable nftables 2>/dev/null || true
    else
        log_info "nftables non disponible, saut"
    fi
    log_success "Pare-feu configuré"
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    log_info "=== Installation des outils de confidentialité ==="

    install_tor
    install_wireguard
    install_dnscrypt
    install_i2p
    install_mat2
    apply_hardening
    setup_firewall

    # Nettoyage
    cd /
    rm -rf "$WORK_DIR"

    log_success "Tous les outils de confidentialité sont installés."
    echo ""
    echo "Résumé des services installés :"
    echo "  - Tor (socks5 sur 9050, control sur 9051)"
    echo "  - WireGuard (wg, wg-quick)"
    echo "  - DNSCrypt-proxy (port 53 local)"
    echo "  - I2P (si Java est présent)"
    echo "  - Mat2 (nettoyeur de métadonnées)"
    echo ""
    echo "Pour activer les services au démarrage :"
    echo "  systemctl enable tor@default  (ou tor.service)"
    echo "  systemctl enable dnscrypt-proxy"
    echo "  systemctl enable i2p (si installé)"
    echo ""
}

main "$@"