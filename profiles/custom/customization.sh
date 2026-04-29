#!/bin/bash
# profiles/custom/customization.sh

set -e

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[0;34m[SUCCESS]\033[0m $1"; }

# Custom environment variables
export CUSTOM_HOME="/opt/custom"
export CUSTOM_CONFIG="/etc/custom"

# Pre-installation hooks
pre_install() {
    log_info "Running pre-installation tasks"
    mkdir -p "$CUSTOM_HOME" "$CUSTOM_CONFIG"
}

# Main installation
install_custom_packages() {
    log_info "Installing custom packages"

    cd /sources

    # Your custom applications
    for pkg in custom-app-*.tar.gz; do
        tar -xzf "$pkg"
        cd "${pkg%.tar.gz}"
        ./configure --prefix=/usr
        make -j$(nproc)
        make install
        cd ..
    done
}

# Post-installation configuration
configure_custom() {
    log_info "Configuring custom environment"

    # Custom systemd service
    cat > /etc/systemd/system/custom.service << EOF
[Unit]
Description=Custom Service
After=network.target

[Service]
Type=simple
ExecStart=$CUSTOM_HOME/bin/custom-daemon
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl enable custom
}

# Main execution
main() {
    pre_install
    install_custom_packages
    configure_custom
    log_success "Custom profile installed"
}

main