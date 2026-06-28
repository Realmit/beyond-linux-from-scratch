#!/bin/bash
# blfs/16-privacy-tools.sh
# Privacy tools installation for LFS/BLFS (gnu-free profile)

set -e

log_info()  { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_success(){ echo -e "\033[0;34m[SUCCESS]\033[0m $1"; }
log_error()  { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

# Directories
SOURCES_DIR="/sources"
INSTALL_DIR="/usr/local"
WORK_DIR="/tmp/privacy-build"

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================
download_and_extract() {
    local url="$1"
    local filename="${url##*/}"
    if [ ! -f "$SOURCES_DIR/$filename" ]; then
        log_info "Downloading $filename..."
        wget -q "$url" -O "$SOURCES_DIR/$filename"
    fi
    tar -xf "$SOURCES_DIR/$filename"
}

# ============================================================================
# 1. TOR
# ============================================================================
install_tor() {
    log_info "Installing Tor..."
    cd "$WORK_DIR"
    download_and_extract "https://dist.torproject.org/tor-0.4.9.7.tar.gz"
    cd tor-0.4.9.7
    ./configure --prefix="$INSTALL_DIR" \
        --sysconfdir=/etc \
        --localstatedir=/var \
        --disable-system-torrc
    make -j$(nproc)
    make install
    # Create dedicated user
    groupadd -r tor 2>/dev/null || true
    useradd -r -g tor -d /var/lib/tor tor 2>/dev/null || true
    mkdir -p /var/lib/tor /var/log/tor
    chown -R tor:tor /var/lib/tor /var/log/tor
    chmod 700 /var/lib/tor
    # Minimal configuration
    cat > /etc/tor/torrc << 'EOF'
# Minimal Tor configuration
DataDirectory /var/lib/tor
Log notice file /var/log/tor/notices.log
SocksPort 9050
ControlPort 9051
EOF
    log_success "Tor installed"
}

# ============================================================================
# 2. WIREGUARD-TOOLS
# ============================================================================
install_wireguard() {
    log_info "Installing WireGuard-tools..."
    cd "$WORK_DIR"
    download_and_extract "https://git.zx2c4.com/wireguard-tools/snapshot/wireguard-tools-1.0.20210914.tar.xz"
    cd wireguard-tools-1.0.20210914/src
    make -j$(nproc)
    make install
    log_success "WireGuard-tools installed"
}

# ============================================================================
# 3. DNSCRYPT-PROXY
# ============================================================================
install_dnscrypt() {
    log_info "Installing DNSCrypt-proxy..."
    cd "$WORK_DIR"
    download_and_extract "https://github.com/DNSCrypt/dnscrypt-proxy/releases/download/2.1.7/dnscrypt-proxy-2.1.7.tar.gz"
    cd dnscrypt-proxy-2.1.7
    make -j$(nproc)
    make install
    mkdir -p /etc/dnscrypt-proxy
    cp example-dnscrypt-proxy.toml /etc/dnscrypt-proxy/dnscrypt-proxy.toml
    # Create user
    groupadd -r dnscrypt 2>/dev/null || true
    useradd -r -g dnscrypt -d /var/empty dnscrypt 2>/dev/null || true
    log_success "DNSCrypt-proxy installed"
}

# ============================================================================
# 4. I2P (all-in-one)
# ============================================================================
install_i2p() {
    log_info "Installing I2P (Java version)..."
    cd "$WORK_DIR"
    # Download Java I2P client (depends on Java)
    if command -v java >/dev/null 2>&1; then
        wget -q "https://download.i2p2.de/releases/2.7.0/i2pinstall_2.7.0.jar" -O i2pinstall.jar
        java -jar i2pinstall.jar -console <<< $'yes\n/opt/i2p'
        # Add user
        groupadd -r i2psvc 2>/dev/null || true
        useradd -r -g i2psvc -d /opt/i2p i2psvc 2>/dev/null || true
        chown -R i2psvc:i2psvc /opt/i2p
        log_success "I2P installed"
    else
        log_info "Java not found, skipping I2P"
    fi
}

# ============================================================================
# 5. MAT2 (metadata anonymizer) – depends on Python
# ============================================================================
install_mat2() {
    log_info "Installing Mat2..."
    cd "$WORK_DIR"
    if command -v python3 >/dev/null 2>&1; then
        download_and_extract "https://0xacab.org/jvoisin/mat2/-/archive/0.13.4/mat2-0.13.4.tar.gz"
        cd mat2-0.13.4
        python3 setup.py install
        log_success "Mat2 installed"
    else
        log_info "Python3 not found, skipping Mat2"
    fi
}

# ============================================================================
# 6. HARDENING (disable services, restrictions)
# ============================================================================
apply_hardening() {
    log_info "Applying privacy hardening..."

    # Disable location services (if present)
    systemctl mask geoclue 2>/dev/null || true

    # Restrict log permissions
    chmod 640 /var/log/* 2>/dev/null || true

    # Disable core dumps
    echo "* hard core 0" >> /etc/security/limits.conf

    # Disable telemetry (example for systemd)
    echo "EnableMetrics=no" >> /etc/systemd/system.conf
    echo "EnableMetrics=no" >> /etc/systemd/user.conf

    log_success "Hardening applied"
}

# ============================================================================
# 7. NETWORK FIREWALL (nftables)
# ============================================================================
setup_firewall() {
    log_info "Configuring basic firewall..."
    # Simple nftables rules to block unnecessary ports
    if command -v nft >/dev/null 2>&1; then
        nft add table inet filter
        nft add chain inet filter input { type filter hook input priority 0\; }
        nft add rule inet filter input ct state established,related accept
        nft add rule inet filter input iif lo accept
        nft add rule inet filter input drop
        # Save configuration (for systemd-nftables)
        nft list ruleset > /etc/nftables.conf
        systemctl enable nftables 2>/dev/null || true
    else
        log_info "nftables not available, skipping"
    fi
    log_success "Firewall configured"
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    log_info "=== Installing privacy tools ==="

    install_tor
    install_wireguard
    install_dnscrypt
    install_i2p
    install_mat2
    apply_hardening
    setup_firewall

    # Cleanup
    cd /
    rm -rf "$WORK_DIR"

    log_success "All privacy tools have been installed."
    echo ""
    echo "Summary of installed services:"
    echo "  - Tor (socks5 on 9050, control on 9051)"
    echo "  - WireGuard (wg, wg-quick)"
    echo "  - DNSCrypt-proxy (local port 53)"
    echo "  - I2P (if Java is present)"
    echo "  - Mat2 (metadata cleaner)"
    echo ""
    echo "To enable services at boot:"
    echo "  systemctl enable tor@default  (or tor.service)"
    echo "  systemctl enable dnscrypt-proxy"
    echo "  systemctl enable i2p (if installed)"
    echo ""
}

main "$@"