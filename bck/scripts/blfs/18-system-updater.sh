#!/bin/bash
# System Update/Upgrade Manager for LFS
# Provides update, upgrade, and rollback capabilities

set -e

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[0;34m[SUCCESS]\033[0m $1"; }
log_warning() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

# ============================================================================
# SYSTEM UPDATE MANAGER (lfs-update)
# ============================================================================
create_update_manager() {
    log_info "Creating system update manager..."

    cat > /usr/local/sbin/lfs-update << 'UPDATER'
#!/bin/bash
# LFS System Update Manager
# Version: 1.0

set -e

VERSION="1.0"
UPDATE_LOG="/var/log/lfs-updates.log"
BACKUP_DIR="/var/backups/lfs"
REPO_URL="${LFS_REPO_URL:-https://repos.linuxfromscratch.org/lfs}"
RELEASE_FILE="/etc/lfs-release"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# ============================================================================
# CHECK FOR UPDATES
# ============================================================================
check_updates() {
    log_info "Checking for system updates..."

    # Get current version
    if [ -f "$RELEASE_FILE" ]; then
        CURRENT_VERSION=$(cat "$RELEASE_FILE")
    else
        CURRENT_VERSION="1.0"
    fi

    # Fetch latest version from repository
    LATEST_VERSION=$(curl -s "${REPO_URL}/latest-version.txt" 2>/dev/null || echo "$CURRENT_VERSION")

    if [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
        log_warning "Update available: $CURRENT_VERSION -> $LATEST_VERSION"
        return 0
    else
        log_info "System is up to date (version: $CURRENT_VERSION)"
        return 1
    fi
}

# ============================================================================
# CREATE BACKUP BEFORE UPDATE
# ============================================================================
create_backup() {
    log_info "Creating system backup before update..."

    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    BACKUP_PATH="${BACKUP_DIR}/backup-${TIMESTAMP}"

    mkdir -p "$BACKUP_PATH"

    # Backup important directories
    for dir in /etc /boot /usr/local /opt /var/lib/lpm; do
        if [ -d "$dir" ]; then
            log_info "Backing up $dir..."
            tar -czf "${BACKUP_PATH}/$(basename $dir).tar.gz" "$dir" 2>/dev/null || true
        fi
    done

    # Backup package database
    if [ -f "/var/lib/lpm/packages.db" ]; then
        cp /var/lib/lpm/packages.db "${BACKUP_PATH}/packages.db"
    fi

    echo "$TIMESTAMP" > "${BACKUP_PATH}/backup-info.txt"
    echo "Pre-update backup" >> "${BACKUP_PATH}/backup-info.txt"

    log_success "Backup created at: $BACKUP_PATH"
    echo "$BACKUP_PATH" > /tmp/last-backup
}

# ============================================================================
# UPDATE LPM PACKAGES
# ============================================================================
update_packages() {
    if command -v lpm &> /dev/null; then
        log_info "Updating LPM packages..."

        # Update repository database
        lpm update

        # Get list of outdated packages
        OUTDATED=$(lpm list-outdated 2>/dev/null || echo "")

        if [ -n "$OUTDATED" ]; then
            log_warning "Outdated packages found:"
            echo "$OUTDATED"

            read -p "Update these packages? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                for pkg in $OUTDATED; do
                    log_info "Updating $pkg..."
                    lpm upgrade "$pkg"
                done
            fi
        else
            log_info "All packages are up to date"
        fi
    fi
}

# ============================================================================
# UPDATE SYSTEM FILES
# ============================================================================
update_system_files() {
    log_info "Updating system files..."

    # Check for new configuration files
    if [ -d "/etc/lfs-updates" ]; then
        for conf in /etc/lfs-updates/*.conf; do
            if [ -f "$conf" ]; then
                TARGET="/etc/$(basename "$conf")"
                if [ -f "$TARGET" ]; then
                    # Create .new file instead of overwriting
                    cp "$conf" "${TARGET}.new"
                    log_warning "New config available: ${TARGET}.new"
                else
                    cp "$conf" "$TARGET"
                fi
            fi
        done
    fi

    # Update kernel if new version available
    if [ -f "/boot/vmlinuz-new" ]; then
        log_info "New kernel available, updating..."
        cp /boot/vmlinuz-new /boot/vmlinuz-lfs
        cp /boot/initramfs-new.img /boot/initramfs-lfs.img
        rm /boot/vmlinuz-new /boot/initramfs-new.img
        log_warning "Kernel updated. Please reboot to apply changes."
    fi
}

# ============================================================================
# UPDATE SYSTEMD SERVICES
# ============================================================================
reload_services() {
    if command -v systemctl &> /dev/null; then
        log_info "Reloading systemd services..."
        systemctl daemon-reload

        # Restart updated services
        for service in $(systemctl list-units --type=service --state=running | grep -E "lfs-|custom-" | cut -d' ' -f1); do
            log_info "Restarting $service"
            systemctl restart "$service" 2>/dev/null || true
        done
    elif [ -d "/etc/rc.d" ]; then
        log_info "Reloading SysV init services..."
        # Re-run rc scripts for updated runlevel
        /etc/rc.d/rc $(runlevel | cut -d' ' -f2) 2>/dev/null || true
    fi
}

# ============================================================================
# ROLLBACK SYSTEM
# ============================================================================
rollback() {
    log_warning "ROLLBACK MODE - Reverting to previous system state"

    if [ ! -d "$BACKUP_DIR" ]; then
        log_error "No backups found"
        return 1
    fi

    # List available backups
    echo "Available backups:"
    ls -1 "$BACKUP_DIR" | grep backup-

    read -p "Enter backup timestamp to restore (e.g., 20240101-120000): " TIMESTAMP

    BACKUP_PATH="${BACKUP_DIR}/backup-${TIMESTAMP}"

    if [ ! -d "$BACKUP_PATH" ]; then
        log_error "Backup not found: $BACKUP_PATH"
        return 1
    fi

    log_info "Restoring from backup: $BACKUP_PATH"

    # Restore directories
    for backup_file in "$BACKUP_PATH"/*.tar.gz; do
        DIR_NAME=$(basename "$backup_file" .tar.gz)
        log_info "Restoring $DIR_NAME..."
        tar -xzf "$backup_file" -C / 2>/dev/null || true
    done

    # Restore package database
    if [ -f "$BACKUP_PATH/packages.db" ]; then
        cp "$BACKUP_PATH/packages.db" /var/lib/lpm/packages.db
    fi

    log_success "Rollback complete! Please reboot."
}

# ============================================================================
# SHOW SYSTEM STATUS
# ============================================================================
show_status() {
    echo ""
    echo "========================================"
    echo "     LFS System Status"
    echo "========================================"

    # Version info
    if [ -f "$RELEASE_FILE" ]; then
        echo "Version: $(cat "$RELEASE_FILE")"
    else
        echo "Version: Unknown"
    fi

    echo "Kernel: $(uname -r)"
    echo "Architecture: $(uname -m)"
    echo "Uptime: $(uptime -p)"
    echo ""

    # Package info
    if command -v lpm &> /dev/null; then
        PKG_COUNT=$(lpm list 2>/dev/null | wc -l)
        echo "Packages installed: $PKG_COUNT"
    fi

    # Service info
    if command -v systemctl &> /dev/null; then
        FAILED_SERVICES=$(systemctl --failed --no-legend | wc -l)
        echo "Failed services: $FAILED_SERVICES"
    fi

    # Last update
    if [ -f "$UPDATE_LOG" ]; then
        LAST_UPDATE=$(tail -1 "$UPDATE_LOG")
        echo "Last update: $LAST_UPDATE"
    fi

    # Available updates
    if check_updates > /dev/null 2>&1; then
        echo ""
        log_warning "Updates available! Run 'lfs-upgrade' to apply."
    fi

    echo "========================================"
}

# ============================================================================
# AUTO-CLEAN OLD BACKUPS
# ============================================================================
clean_old_backups() {
    log_info "Cleaning old backups (keeping last 5)..."

    cd "$BACKUP_DIR"
    ls -1d backup-* 2>/dev/null | head -n -5 | while read backup; do
        log_info "Removing old backup: $backup"
        rm -rf "$backup"
    done
}

# ============================================================================
# MAIN COMMAND HANDLER
# ============================================================================
case "${1:-help}" in
    check)
        check_updates
        ;;
    upgrade|update)
        echo "========================================"
        echo "  LFS System Update"
        echo "========================================"

        # Check for updates
        if ! check_updates; then
            echo "No updates available."
            exit 0
        fi

        # Create backup
        create_backup

        # Update packages
        update_packages

        # Update system files
        update_system_files

        # Reload services
        reload_services

        # Log update
        echo "$(date): System upgraded to version $(curl -s ${REPO_URL}/latest-version.txt 2>/dev/null || echo 'unknown')" >> "$UPDATE_LOG"

        # Clean old backups
        clean_old_backups

        log_success "System update completed!"
        echo ""
        echo "If you experience issues, rollback with: lfs-update rollback"
        echo "A reboot is recommended."
        ;;
    rollback)
        rollback
        ;;
    status)
        show_status
        ;;
    clean)
        clean_old_backups
        ;;
    help|--help|-h)
        cat << 'HELP'
LFS System Update Manager

Usage:
  lfs-update check           Check for available updates
  lfs-update upgrade         Perform system upgrade
  lfs-update rollback        Rollback to previous state
  lfs-update status          Show system status
  lfs-update clean           Clean old backups

Options:
  --no-backup               Skip backup before upgrade
  --force                   Force upgrade even if conflicts
  --dry-run                 Simulate upgrade without changes

HELP
        ;;
    *)
        log_error "Unknown command: $1"
        echo "Run 'lfs-update help' for usage"
        exit 1
        ;;
esac
UPDATER

    chmod +x /usr/local/sbin/lfs-update

    log_success "Update manager created: lfs-update"
}

# ============================================================================
# RELEASE VERSION FILE
# ============================================================================
create_release_file() {
    log_info "Creating release version file..."

    LFS_VERSION="${LFS_VERSION:-3.0.0}"

    cat > "$LFS/etc/lfs-release" << EOF
LFS Linux ${LFS_VERSION}
EOF

    cat > "$LFS/etc/os-release" << 'OSRELEASE'
NAME="LFS Linux"
VERSION="3.0.0"
ID=lfs
ID_LIKE="linux"
PRETTY_NAME="LFS Linux 3.0.0"
VERSION_ID="3.0.0"
HOME_URL="https://www.linuxfromscratch.org/"
SUPPORT_URL="https://github.com/lfs-builder"
BUG_REPORT_URL="https://github.com/lfs-builder/issues"
EOF

    # Create LSB release
    cat > "$LFS/etc/lsb-release" << 'LSBRELEASE'
DISTRIB_ID="LFS Linux"
DISTRIB_RELEASE="3.0.0"
DISTRIB_CODENAME="stable"
DISTRIB_DESCRIPTION="LFS Linux 3.0.0"
LSBRELEASE
}

# ============================================================================
# CRON JOB FOR AUTO-UPDATE CHECKS
# ============================================================================
create_cron_job() {
    log_info "Creating automatic update check cron job..."

    cat > "$LFS/etc/cron.daily/lfs-update-check" << 'CRON'
#!/bin/bash
# Daily update check

/usr/local/sbin/lfs-update check > /var/log/update-check.log 2>&1

# Send email if updates available
if grep -q "Update available" /var/log/update-check.log; then
    echo "System updates available. Run 'lfs-update upgrade'" | mail -s "LFS Updates Available" root
fi
CRON

    chmod +x "$LFS/etc/cron.daily/lfs-update-check"

    log_success "Automatic update check configured (daily)"
}

# ============================================================================
# SYSTEMD UPDATE TIMER
# ============================================================================
create_systemd_timer() {
    if [ -d "$LFS/usr/lib/systemd" ]; then
        log_info "Creating systemd update timer..."

        cat > "$LFS/etc/systemd/system/lfs-update-check.service" << 'EOF'
[Unit]
Description=LFS Update Check Service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/lfs-update check
StandardOutput=journal
EOF

        cat > "$LFS/etc/systemd/system/lfs-update-check.timer" << 'EOF'
[Unit]
Description=LFS Update Check Timer
Requires=lfs-update-check.service

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

        chmod 644 "$LFS/etc/systemd/system/lfs-update-check."*

        log_success "Systemd update timer created"
    fi
}

# ============================================================================
# UPGRADE NOTIFICATION SCRIPT
# ============================================================================
create_upgrade_notification() {
    log_info "Creating upgrade notification script..."

    cat > "$LFS/usr/local/sbin/check-updates" << 'EOF'
#!/bin/bash
# Quick update check for MOTD

if [ -f /var/run/.update-available ]; then
    echo "  ⚡ Updates available! Run 'lfs-update upgrade'"
fi
EOF

    chmod +x "$LFS/usr/local/sbin/check-updates"

    # Add to profile for login message
    cat >> "$LFS/etc/profile" << 'EOF'

# Show update status
if [ -x /usr/local/sbin/check-updates ]; then
    /usr/local/sbin/check-updates
fi
EOF

    log_success "Upgrade notification configured"
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    log_info "=== SYSTEM UPDATE MANAGER SETUP ==="

    create_backup_dirs
    create_update_manager
    create_release_file
    create_cron_job
    create_systemd_timer
    create_upgrade_notification

    log_success "System update/upgrade system installed!"
    echo ""
    echo "Commands available:"
    echo "  lfs-update check     - Check for updates"
    echo "  lfs-update upgrade   - Perform system upgrade"
    echo "  lfs-update rollback  - Rollback to previous state"
    echo "  lfs-update status    - Show system status"
    echo ""
    echo "Automatic daily update check enabled"
}

# Create backup directories
create_backup_dirs() {
    mkdir -p "$LFS/var/backups/lfs"
    mkdir -p "$LFS/var/log"
    mkdir -p "$LFS/etc/lfs-updates"
    touch "$LFS/var/log/lfs-updates.log"
}

main "$@"