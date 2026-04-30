#!/bin/bash
# Custom Profile for LFS
# User-defined custom build template

set -e

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }
log_warning() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }
log_success() { echo -e "\033[0;34m[SUCCESS]\033[0m $1"; }

# ============================================================================
# CUSTOM CONFIGURATION
# ============================================================================

# Edit these variables for your custom build
CUSTOM_NAME="${CUSTOM_NAME:-My Custom LFS}"
CUSTOM_VERSION="${CUSTOM_VERSION:-1.0.0}"
CUSTOM_HOME="/opt/${CUSTOM_NAME,,}"
CUSTOM_CONFIG="/etc/${CUSTOM_NAME,,}"
CUSTOM_USER="${CUSTOM_USER:-lfsuser}"
NUM_JOBS=${NUM_JOBS:-$(nproc)}
PACKAGE_LIST="profiles/custom/packages.list"

# ============================================================================
# LOAD CUSTOM PACKAGES
# ============================================================================
load_custom_packages() {
    log_info "Loading custom package list from $PACKAGE_LIST..."

    if [ -f "$PACKAGE_LIST" ]; then
        # Parse packages.list (skip comments and empty lines)
        CUSTOM_PACKAGES=$(grep -v '^#' "$PACKAGE_LIST" | grep -v '^$' | grep -v '^#=' | tr '\n' ' ')
        log_info "Packages to install: $CUSTOM_PACKAGES"
    else
        log_warning "Package list not found: $PACKAGE_LIST"
        log_info "Using default custom packages"
        CUSTOM_PACKAGES="git vim htop"
    fi
}

# ============================================================================
# PRE-INSTALLATION HOOKS
# ============================================================================
pre_install() {
    log_info "Running pre-installation tasks..."

    # Create custom directories
    mkdir -p "$CUSTOM_HOME" "$CUSTOM_CONFIG"
    mkdir -p "$CUSTOM_HOME"/{bin,lib,etc,logs,data}
    mkdir -p /var/log/custom
    mkdir -p /var/lib/custom

    # Set permissions
    chmod 755 "$CUSTOM_HOME"
    chown -R ${CUSTOM_USER}:${CUSTOM_USER} "$CUSTOM_HOME" 2>/dev/null || true

    log_success "Pre-installation complete"
}

# ============================================================================
# INSTALL CUSTOM PACKAGES
# ============================================================================
install_custom_packages() {
    log_info "Installing custom packages..."

    cd /sources

    # Method 1: Install from package list using LPM
    if command -v lpm &> /dev/null && [ -n "$CUSTOM_PACKAGES" ]; then
        log_info "Installing packages via LPM..."
        lpm update
        for pkg in $CUSTOM_PACKAGES; do
            if lpm list | grep -q "^$pkg"; then
                log_info "Installing $pkg from repository..."
                lpm install "$pkg"
            else
                log_info "Package $pkg not found in repositories"
            fi
        done
    fi

    # Method 2: Install from source tarballs
    log_info "Looking for custom source packages..."
    for pkg in custom-*.tar.gz custom-*.tar.xz custom-*.tgz; do
        if [ -f "$pkg" ]; then
            log_info "Building $pkg from source..."
            tar -xf "$pkg"
            PKG_DIR="${pkg%.tar.*}"
            cd "$PKG_DIR"

            if [ -f "configure" ]; then
                ./configure --prefix=/usr
            elif [ -f "CMakeLists.txt" ]; then
                mkdir -p build && cd build
                cmake -DCMAKE_INSTALL_PREFIX=/usr ..
                cd ..
            elif [ -f "meson.build" ]; then
                meson setup --prefix=/usr build
                cd build
            fi

            make -j$NUM_JOBS
            make install
            cd /sources
        fi
    done

    log_success "Custom packages installed"
}

# ============================================================================
# INSTALL CUSTOM SERVICE
# ============================================================================
install_custom_service() {
    log_info "Configuring custom service..."

    # Create custom daemon script (example)
    if [ ! -f "$CUSTOM_HOME/bin/custom-daemon" ]; then
        cat > "$CUSTOM_HOME/bin/custom-daemon" << EOF
#!/bin/bash
# Custom Daemon for $CUSTOM_NAME
# Version: $CUSTOM_VERSION

echo "\$(date): Custom daemon started" >> /var/log/custom/daemon.log

while true; do
    # Add your custom logic here
    sleep 60
done
EOF
        chmod +x "$CUSTOM_HOME/bin/custom-daemon"
    fi

    # Create systemd service (if systemd is used)
    if command -v systemctl &> /dev/null; then
        cat > /etc/systemd/system/custom.service << EOF
[Unit]
Description=${CUSTOM_NAME} Service
After=network.target
Documentation=file://${CUSTOM_CONFIG}/README.md

[Service]
Type=simple
User=${CUSTOM_USER}
Group=${CUSTOM_USER}
WorkingDirectory=${CUSTOM_HOME}
EnvironmentFile=-${CUSTOM_CONFIG}/environment.conf
ExecStart=${CUSTOM_HOME}/bin/custom-daemon
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

        systemctl daemon-reload
        systemctl enable custom
    fi

    # Create SysV init script (alternative)
    if [ -d "/etc/rc.d" ]; then
        cat > "/etc/rc.d/init.d/custom" << EOF
#!/bin/sh
# Custom init script for ${CUSTOM_NAME}

DAEMON="${CUSTOM_HOME}/bin/custom-daemon"
PIDFILE="/var/run/custom.pid"

case "\$1" in
    start)
        echo "Starting ${CUSTOM_NAME}..."
        start-stop-daemon --start --quiet --pidfile \$PIDFILE --exec \$DAEMON
        ;;
    stop)
        echo "Stopping ${CUSTOM_NAME}..."
        start-stop-daemon --stop --quiet --pidfile \$PIDFILE
        rm -f \$PIDFILE
        ;;
    restart)
        \$0 stop
        sleep 1
        \$0 start
        ;;
    status)
        status_of_proc -p \$PIDFILE \$DAEMON custom
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart|status}"
        exit 1
        ;;
esac
EOF
        chmod +x "/etc/rc.d/init.d/custom"
    fi

    log_success "Custom service configured"
}

# ============================================================================
# CREATE CUSTOM ENVIRONMENT
# ============================================================================
configure_custom_environment() {
    log_info "Configuring custom environment..."

    # Environment file
    cat > "$CUSTOM_CONFIG/environment.conf" << EOF
# ${CUSTOM_NAME} Environment Configuration
CUSTOM_HOME=${CUSTOM_HOME}
CUSTOM_CONFIG=${CUSTOM_CONFIG}
CUSTOM_VERSION=${CUSTOM_VERSION}
CUSTOM_NAME="${CUSTOM_NAME}"
PATH=\$PATH:${CUSTOM_HOME}/bin
EOF

    # Profile script
    cat > "/etc/profile.d/custom.sh" << EOF
# ${CUSTOM_NAME} Environment
export CUSTOM_HOME=${CUSTOM_HOME}
export CUSTOM_CONFIG=${CUSTOM_CONFIG}
export CUSTOM_VERSION=${CUSTOM_VERSION}
export PATH=\$PATH:${CUSTOM_HOME}/bin
EOF
    chmod +x /etc/profile.d/custom.sh

    # Create README
    cat > "$CUSTOM_CONFIG/README.md" << EOF
# $CUSTOM_NAME v$CUSTOM_VERSION

## Installation Directory
- Applications: $CUSTOM_HOME
- Configuration: $CUSTOM_CONFIG
- Logs: /var/log/custom
- Data: /var/lib/custom

## Services
- Service name: custom
- Start: systemctl start custom
- Stop: systemctl stop custom
- Status: systemctl status custom

## Custom Scripts
Add your custom scripts to $CUSTOM_HOME/bin/

## Configuration
Edit $CUSTOM_CONFIG/environment.conf to change settings

## Logs
View logs at /var/log/custom/daemon.log
EOF

    log_success "Custom environment configured"
}

# ============================================================================
# ADD CUSTOM ALIASES
# ============================================================================
configure_custom_aliases() {
    log_info "Adding custom aliases..."

    cat >> "/home/${CUSTOM_USER}/.bashrc" << EOF

# ============================================================================
# ${CUSTOM_NAME} Aliases
# ============================================================================

alias custom-start='sudo systemctl start custom'
alias custom-stop='sudo systemctl stop custom'
alias custom-restart='sudo systemctl restart custom'
alias custom-status='sudo systemctl status custom'
alias custom-logs='sudo journalctl -u custom -f'
alias custom-config='cd ${CUSTOM_CONFIG}'
alias custom-home='cd ${CUSTOM_HOME}'
alias custom-edit='${EDITOR:-vim} ${CUSTOM_CONFIG}/environment.conf'

# Custom commands
alias custom-info='echo "${CUSTOM_NAME} v${CUSTOM_VERSION}"'
EOF

    chown "${CUSTOM_USER}:${CUSTOM_USER}" "/home/${CUSTOM_USER}/.bashrc" 2>/dev/null || true

    log_success "Custom aliases configured"
}

# ============================================================================
# CREATE CUSTOM FILESYSTEM HOOKS
# ============================================================================
configure_custom_fsh() {
    log_info "Configuring custom filesystem hierarchy..."

    # Add custom paths to systemd-tmpfiles
    if [ -d "/usr/lib/tmpfiles.d" ]; then
        cat > "/usr/lib/tmpfiles.d/custom.conf" << EOF
# Custom directories
d ${CUSTOM_HOME} 0755 ${CUSTOM_USER} ${CUSTOM_USER} -
d ${CUSTOM_CONFIG} 0755 root root -
d /var/log/custom 0755 ${CUSTOM_USER} ${CUSTOM_USER} -
d /var/lib/custom 0755 ${CUSTOM_USER} ${CUSTOM_USER} -
EOF
    fi

    log_success "Custom filesystem hooks configured"
}

# ============================================================================
# CREATE BACKUP SCRIPT
# ============================================================================
create_backup_script() {
    log_info "Creating custom backup script..."

    cat > "/usr/local/sbin/backup-custom.sh" << EOF
#!/bin/bash
# Backup script for ${CUSTOM_NAME}

BACKUP_DIR="/backups/custom"
TIMESTAMP=\$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="\${BACKUP_DIR}/custom-backup-\${TIMESTAMP}.tar.gz"

mkdir -p "\$BACKUP_DIR"

tar -czf "\$BACKUP_FILE" \\
    "$CUSTOM_HOME" \\
    "$CUSTOM_CONFIG" \\
    /var/log/custom \\
    /var/lib/custom

echo "Custom backup created: \$BACKUP_FILE"
EOF

    chmod +x /usr/local/sbin/backup-custom.sh

    # Add to cron if available
    if [ -d "/etc/cron.daily" ]; then
        ln -sf /usr/local/sbin/backup-custom.sh /etc/cron.daily/backup-custom 2>/dev/null || true
    fi

    log_success "Backup script created"
}

# ============================================================================
# POST-INSTALLATION SCRIPT HANDLER
# ============================================================================
run_post_install_scripts() {
    log_info "Running post-installation scripts..."

    # Run custom post-install script if exists
    if [ -f "packages/custom-scripts/custom-post-install.sh" ]; then
        log_info "Executing custom post-install script..."
        bash packages/custom-scripts/custom-post-install.sh
    fi

    # Run user-defined scripts
    if [ -d "$CUSTOM_CONFIG/post-install.d" ]; then
        for script in "$CUSTOM_CONFIG/post-install.d"/*.sh; do
            if [ -f "$script" ]; then
                log_info "Running $script..."
                bash "$script"
            fi
        done
    fi

    log_success "Post-installation complete"
}

# ============================================================================
# CLEANUP
# ============================================================================
cleanup() {
    log_info "Cleaning up temporary files..."

    cd /sources
    rm -rf custom-*.tar.* 2>/dev/null || true
    rm -rf custom-*/ 2>/dev/null || true

    log_success "Cleanup complete"
}

# ============================================================================
# STATUS REPORT
# ============================================================================
show_status() {
    log_success "========================================="
    log_success "${CUSTOM_NAME} v${CUSTOM_VERSION} Installed!"
    log_success "========================================="
    echo ""
    echo "Installation Summary:"
    echo "  Name:       $CUSTOM_NAME"
    echo "  Version:    $CUSTOM_VERSION"
    echo "  User:       $CUSTOM_USER"
    echo "  Home:       $CUSTOM_HOME"
    echo "  Config:     $CUSTOM_CONFIG"
    echo ""
    echo "Services:"
    echo "  systemctl start custom    - Start custom service"
    echo "  systemctl stop custom     - Stop custom service"
    echo "  systemctl status custom   - Check status"
    echo ""
    echo "Commands:"
    echo "  custom-start              - Start custom service (alias)"
    echo "  custom-stop               - Stop custom service"
    echo "  custom-status             - Check status"
    echo "  custom-logs               - View logs"
    echo "  backup-custom.sh          - Backup custom data"
    echo ""
    echo "Directories:"
    echo "  $CUSTOM_HOME              - Applications"
    echo "  $CUSTOM_CONFIG            - Configuration"
    echo "  /var/log/custom           - Logs"
    echo "  /var/lib/custom           - Data"
    echo ""
    echo "Customization:"
    echo "  Edit $CUSTOM_CONFIG/environment.conf"
    echo "  Add scripts to $CUSTOM_HOME/bin/"
    echo "========================================="
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    log_info "========================================="
    log_info "Custom Profile Installation: $CUSTOM_NAME"
    log_info "========================================="

    load_custom_packages
    pre_install
    install_custom_packages
    install_custom_service
    configure_custom_environment
    configure_custom_aliases
    configure_custom_fsh
    create_backup_script
    run_post_install_scripts
    cleanup
    show_status

    log_success "Custom profile installation complete!"
}

# Run main function
main "$@"