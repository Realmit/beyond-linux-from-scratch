#!/bin/bash
# Privacy-focused tools for LFS

set -e

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }

install_privacy_tools() {
    log_info "Installing privacy tools"

    cd /sources

    # WireGuard (VPN)
    tar -xf wireguard-tools-*.tar.xz
    cd wireguard-tools-*
    make -j$(nproc)
    make install

    # Tor
    tar -xf tor-*.tar.gz
    cd tor-*
    ./configure --prefix=/usr
    make -j$(nproc)
    make install

    # Configure Tor as a service
    useradd -r -s /bin/false tor
    cat > /etc/systemd/system/tor.service << 'EOF'
[Unit]
Description=Tor daemon
After=network.target

[Service]
User=tor
Group=tor
Type=simple
ExecStart=/usr/bin/tor
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    # DNSCrypt (encrypted DNS)
    tar -xf dnscrypt-proxy-*.tar.gz
    cd dnscrypt-proxy-*
    cp linux-x86_64/dnscrypt-proxy /usr/local/bin/
    mkdir -p /etc/dnscrypt-proxy
    cp example-dnscrypt-proxy.toml /etc/dnscrypt-proxy/dnscrypt-proxy.toml

    # Configure for privacy
    sed -i 's/#  force_tcp = false/  force_tcp = true/' /etc/dnscrypt-proxy/dnscrypt-proxy.toml
    sed -i 's/server_names =.*/server_names = ["cloudflare", "quad9-dnscrypt-ip4-filter-pri", "dnscrypt.eu-dk"]/' /etc/dnscrypt-proxy/dnscrypt-proxy.toml

    # Browser privacy settings for Firefox
    if [ -d /usr/lib/firefox ]; then
        cat > /usr/lib/firefox/defaults/pref/privacy.js << 'EOF'
// Privacy settings
pref("privacy.donottrackheader.enabled", true);
pref("privacy.trackingprotection.enabled", true);
pref("privacy.trackingprotection.fingerprinting.enabled", true);
pref("privacy.trackingprotection.cryptomining.enabled", true);
pref("media.peerconnection.enabled", false);
pref("webgl.disabled", true);
pref("geo.enabled", false);
pref("browser.safebrowsing.enabled", false);
pref("browser.safebrowsing.malware.enabled", false);
pref("dom.battery.enabled", false);
pref("network.cookie.lifetimePolicy", 2);
pref("network.cookie.alwaysAcceptSessionCookies", true);
EOF
    fi

    log_success "Privacy tools installed"
}

install_privacy_tools