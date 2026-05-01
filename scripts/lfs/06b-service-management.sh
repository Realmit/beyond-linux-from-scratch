#!/bin/bash
# Service Management Abstraction Layer
# Provides unified service commands regardless of init system

set -e

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_warning() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }

INIT_SYSTEM="${INIT_SYSTEM:-systemd}"

# Detect init system
detect_init() {
    if [ -f /usr/lib/systemd/systemd ] && command -v systemctl >/dev/null; then
        echo "systemd"
    elif [ -f /sbin/init ] && grep -q sysvinit /sbin/init 2>/dev/null; then
        echo "sysv"
    elif [ -f /sbin/openrc-run ]; then
        echo "openrc"
    elif [ -f /usr/bin/runsvdir ]; then
        echo "runit"
    elif [ -f /usr/bin/s6-svscan ]; then
        echo "s6"
    else
        echo "unknown"
    fi
}

# Unified service command
create_service_abstraction() {
    log_info "Creating service management abstraction"

    # Créer le répertoire si nécessaire (pour Docker)
    if [ ! -d /usr/local/bin ]; then
        mkdir -p /usr/local/bin 2>/dev/null || true
    fi

    cat > /usr/local/bin/svc << 'SVCEOF'
#!/bin/bash
# Unified service command wrapper

detect_init() {
    if [ -f /usr/lib/systemd/systemd ] && command -v systemctl >/dev/null; then
        echo "systemd"
    elif [ -f /sbin/init ] && grep -q sysvinit /sbin/init 2>/dev/null; then
        echo "sysv"
    elif [ -f /sbin/openrc-run ]; then
        echo "openrc"
    elif [ -f /usr/bin/runsvdir ]; then
        echo "runit"
    elif [ -f /usr/bin/s6-svscan ]; then
        echo "s6"
    else
        echo "unknown"
    fi
}

INIT_SYSTEM=$(detect_init 2>/dev/null || echo "systemd")

service_action() {
    local action=$1
    local service=$2

    case $INIT_SYSTEM in
        systemd)
            if command -v systemctl >/dev/null; then
                systemctl $action $service 2>/dev/null || echo "Service $service: systemctl $action failed"
            else
                echo "systemctl not available"
            fi
            ;;
        sysv)
            if [ -f "/etc/rc.d/init.d/$service" ]; then
                /etc/rc.d/init.d/$service $action
            else
                echo "Service $service not found"
                exit 1
            fi
            ;;
        openrc)
            if command -v rc-service >/dev/null; then
                rc-service $service $action
            else
                echo "rc-service not available"
            fi
            ;;
        runit|s6)
            if [ -d "/etc/runit/runsvdir/default/$service" ] || [ -d "/etc/s6/servicedb/$service" ]; then
                sv $action $service 2>/dev/null || s6-svc -$action /etc/s6/servicedb/$service 2>/dev/null
            else
                echo "Service $service not found"
                exit 1
            fi
            ;;
        *)
            echo "Unknown init system"
            exit 1
            ;;
    esac
}

case "$1" in
    start|stop|restart|status|enable|disable)
        if [ -z "$2" ]; then
            echo "Usage: $0 <action> <service>"
            exit 1
        fi
        shift
        service_action "$@"
        ;;
    list)
        case $INIT_SYSTEM in
            systemd) systemctl list-units --type=service 2>/dev/null || echo "systemctl not available" ;;
            sysv) ls /etc/rc.d/init.d/ 2>/dev/null || echo "No sysv services" ;;
            openrc) rc-service -l 2>/dev/null || echo "rc-service not available" ;;
            runit) ls /etc/runit/runsvdir/default/ 2>/dev/null || echo "No runit services" ;;
            s6) ls /etc/s6/servicedb/ 2>/dev/null || echo "No s6 services" ;;
        esac
        ;;
    *)
        echo "Usage: svc {start|stop|restart|status|enable|disable|list} [service]"
        echo ""
        echo "Unified service management for:"
        echo "  systemd, SysV init, OpenRC, runit, s6"
        ;;
esac
SVCEOF

    if [ -f /usr/local/bin/svc ]; then
        chmod +x /usr/local/bin/svc
        log_info "Service abstraction created: 'svc' command available"
    else
        log_warning "Could not create svc command (permission denied?)"
    fi

    # Create compatibility aliases (dans /etc/profile.d si possible)
    if [ -d /etc/profile.d ]; then
        cat > /etc/profile.d/svc-alias.sh << 'EOF'
# Service management aliases
alias sv-start='svc start'
alias sv-stop='svc stop'
alias sv-restart='svc restart'
alias sv-status='svc status'
alias sv-list='svc list'
alias sv-enable='svc enable'
alias sv-disable='svc disable'
EOF
        chmod +x /etc/profile.d/svc-alias.sh 2>/dev/null || true
        log_info "Aliases created in /etc/profile.d/svc-alias.sh"
    else
        log_warning "Could not create aliases (/etc/profile.d not writable)"
    fi
}

# Main
detect_init
create_service_abstraction

log_info "Service abstraction setup complete"