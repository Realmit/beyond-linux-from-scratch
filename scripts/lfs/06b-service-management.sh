#!/bin/bash
# Service Management Abstraction Layer
# Provides unified service commands regardless of init system

set -e

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }

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

    cat > /usr/local/bin/svc << 'SVCEOF'
#!/bin/bash
# Unified service command wrapper

INIT_SYSTEM=$(detect_init 2>/dev/null || echo "systemd")

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

service_action() {
    local action=$1
    local service=$2

    case $INIT_SYSTEM in
        systemd)
            systemctl $action $service
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
            rc-service $service $action
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
            systemd) systemctl list-units --type=service ;;
            sysv) ls /etc/rc.d/init.d/ ;;
            openrc) rc-service -l ;;
            runit) ls /etc/runit/runsvdir/default/ ;;
            s6) ls /etc/s6/servicedb/ ;;
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

    chmod +x /usr/local/bin/svc

    # Create compatibility aliases
    cat >> /etc/profile.d/svc-alias.sh << 'EOF'
# Service management aliases
alias sv-start='svc start'
alias sv-stop='svc stop'
alias sv-restart='svc restart'
alias sv-status='svc status'
alias sv-list='svc list'
alias sv-enable='svc enable'
alias sv-disable='svc disable'
EOF

    log_info "Service abstraction created: 'svc' command available"
}

# Main
detect_init
create_service_abstraction