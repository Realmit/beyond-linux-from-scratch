#!/bin/bash
# systemd Configuration
# Modern init system setup

set -e

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[0;34m[SUCCESS]\033[0m $1"; }

log_info "Configuring systemd"

# S'assurer que systemd est installé
if [ ! -f /usr/lib/systemd/systemd ]; then
    log_warning "systemd not found, skipping configuration"
    exit 0
fi

# Créer machine-id (requis)
if [ ! -f /etc/machine-id ]; then
    systemd-machine-id-setup
fi

# Définir le target par défaut
if [ -f /usr/bin/startx ] || [ -f /usr/bin/xinit ]; then
    systemctl set-default graphical.target 2>/dev/null || true
    log_info "Default target: graphical.target"
else
    systemctl set-default multi-user.target 2>/dev/null || true
    log_info "Default target: multi-user.target"
fi

# Configuration réseau
mkdir -p /etc/systemd/network
cat > /etc/systemd/network/20-dhcp.network << 'EOF'
[Match]
Name=en*
Name=eth*

[Network]
DHCP=yes
IPv6PrivacyExtensions=yes

[DHCP]
RouteMetric=10
EOF

cat > /etc/systemd/network/10-loopback.network << 'EOF'
[Match]
Name=lo

[Network]
LinkLocalAddressing=no
EOF

# Configuration journald
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/lfs.conf << 'EOF'
[Journal]
SystemMaxUse=500M
Compress=yes
ForwardToSyslog=no
EOF

# Configuration résolv.conf
if [ -f /usr/lib/systemd/systemd-resolved ]; then
    systemctl enable systemd-resolved 2>/dev/null || true
    ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
fi

# Configuration timesyncd
if [ -f /usr/lib/systemd/systemd-timesyncd ]; then
    systemctl enable systemd-timesyncd 2>/dev/null || true
fi

# Surcharge pour getty (auto-login optionnel)
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -- \\u' --noclear -a root %I $TERM
Restart=always
RestartSec=0
EOF

# Désactiver les services non nécessaires
for svc in systemd-firstboot systemd-sysusers; do
    systemctl mask $svc 2>/dev/null || true
done

# Recharger systemd
systemctl daemon-reload 2>/dev/null || true

log_success "systemd configured"