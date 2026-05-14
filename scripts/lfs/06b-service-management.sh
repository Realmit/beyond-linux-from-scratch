#!/bin/bash
# Service Management Abstraction Layer
# Provides unified 'svc' command for all init systems

set -e

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[0;34m[SUCCESS]\033[0m $1"; }

INIT_SYSTEM="${INIT_SYSTEM:-sysvinit}"

# Détection automatique de l'init system
detect_init() {
    if [ -f /usr/lib/systemd/systemd ] && command -v systemctl >/dev/null 2>&1; then
        echo "systemd"
    elif [ -f /sbin/init ] && strings /sbin/init 2>/dev/null | grep -q "sysvinit"; then
        echo "sysvinit"
    elif [ -d /etc/rc.d/init.d ] && [ -f /etc/inittab ]; then
        echo "sysvinit"
    else
        echo "$INIT_SYSTEM"
    fi
}

ACTUAL_INIT=$(detect_init)
log_info "Detected init system: $ACTUAL_INIT"

# Créer la commande unifiée 'svc'
cat > /usr/local/bin/svc << 'SVCEOF'
#!/bin/bash
# Unified service management command
# Works with: systemd, sysvinit, openrc, runit, s6

# Detect init system
detect_init() {
    if [ -f /usr/lib/systemd/systemd ] && command -v systemctl >/dev/null 2>&1; then
        echo "systemd"
    elif [ -f /sbin/init ] && strings /sbin/init 2>/dev/null | grep -q "sysvinit"; then
        echo "sysvinit"
    elif [ -d /etc/rc.d/init.d ] && [ -f /etc/inittab ]; then
        echo "sysvinit"
    elif command -v rc-service >/dev/null 2>&1; then
        echo "openrc"
    elif command -v runsvdir >/dev/null 2>&1; then
        echo "runit"
    else
        echo "unknown"
    fi
}

INIT_SYS=$(detect_init)

case "$INIT_SYS" in
    systemd)
        case "$1" in
            start|stop|restart|status|enable|disable|reload|isolate)
                systemctl "$1" "$2"
                ;;
            list)
                systemctl list-units --type=service
                ;;
            *)
                echo "Usage: svc {start|stop|restart|status|enable|disable|list} [service]"
                ;;
        esac
        ;;

    sysvinit)
        SVC_DIR="/etc/rc.d/init.d"
        case "$1" in
            start|stop|restart|status)
                if [ -x "$SVC_DIR/$2" ]; then
                    "$SVC_DIR/$2" "$1"
                else
                    echo "Service $2 not found"
                    exit 1
                fi
                ;;
            enable)
                # Créer les liens symboliques pour les runlevels 2-5
                for rl in 2 3 4 5; do
                    ln -sf "$SVC_DIR/$2" "/etc/rc.d/rc$rl.d/S??$2"
                done
                for rl in 0 1 6; do
                    ln -sf "$SVC_DIR/$2" "/etc/rc.d/rc$rl.d/K??$2"
                done
                ;;
            disable)
                find /etc/rc.d -name "*$2" -exec rm -f {} \;
                ;;
            list)
                ls -1 "$SVC_DIR"
                ;;
            *)
                echo "Usage: svc {start|stop|restart|status|enable|disable|list} [service]"
                ;;
        esac
        ;;

    *)
        echo "Unknown init system: $INIT_SYS"
        echo "Available commands may be limited"
        ;;
esac
SVCEOF

chmod 755 /usr/local/bin/svc

# Créer des alias dans /etc/profile.d
mkdir -p /etc/profile.d
cat > /etc/profile.d/svc-aliases.sh << 'EOF'
# Service management aliases
alias sv-start='svc start'
alias sv-stop='svc stop'
alias sv-restart='svc restart'
alias sv-status='svc status'
alias sv-enable='svc enable'
alias sv-disable='svc disable'
alias sv-list='svc list'
EOF
chmod 644 /etc/profile.d/svc-aliases.sh

log_success "Service abstraction created: 'svc' command available"