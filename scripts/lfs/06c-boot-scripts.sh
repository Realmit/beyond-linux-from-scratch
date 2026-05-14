#!/bin/bash
# SysVinit Boot Scripts
# Supports both LFS Classic and BSD-style init

set -e

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[0;34m[SUCCESS]\033[0m $1"; }

SYSVINIT_STYLE="${SYSVINIT_STYLE:-lfs-classic}"

log_info "Configuring sysvinit boot scripts (style: $SYSVINIT_STYLE)"

# Créer la structure des répertoires
mkdir -p /etc/rc.d/{init.d,rc0.d,rc1.d,rc2.d,rc3.d,rc4.d,rc5.d,rc6.d}

case "$SYSVINIT_STYLE" in
    lfs-classic)
        # ====================================================================
        # LFS CLASSIC STYLE - Original LFS bootscripts
        # ====================================================================
        log_info "Installing LFS classic bootscripts"

        cd /sources
        if [ -f lfs-bootscripts-20240825.tar.xz ]; then
            tar -xf lfs-bootscripts-20240825.tar.xz
            cd lfs-bootscripts-20240825
            make install
            cd ..
        fi

        # Script rc principal
        cat > /etc/rc.d/rc << 'EOF'
#!/bin/bash
# LFS Classic RC script

runlevel=$1

if [ -z "$runlevel" ]; then
    echo "Usage: $0 <runlevel>"
    exit 1
fi

for script in /etc/rc.d/rc${runlevel}.d/[SK]*; do
    if [ -x "$script" ]; then
        $script
    fi
done
EOF
        chmod 755 /etc/rc.d/rc
        ;;

    bsd-style)
        # ====================================================================
        # BSD-STYLE INIT - /etc/rc.d structure like FreeBSD
        # ====================================================================
        log_info "Installing BSD-style init scripts"

        # Script rc principal (BSD style)
        cat > /etc/rc << 'EOF'
#!/bin/sh
# BSD-style system startup script

. /etc/rc.subr

# Load configuration
load_rc_config

# Run startup scripts
for script in /etc/rc.d/rcS.d/[0-9]*; do
    [ -x "$script" ] && $script start
done

# Start services for current runlevel
runlevel=$(/sbin/runlevel | cut -d' ' -f2)
for script in /etc/rc.d/rc${runlevel}.d/[0-9]*; do
    [ -x "$script" ] && $script start
done
EOF
        chmod 755 /etc/rc

        # rc.subr (fonctions communes BSD)
        cat > /etc/rc.subr << 'EOF'
#!/bin/sh
# rc.subr - common functions for BSD-style init

load_rc_config() {
    for conf in /etc/rc.conf /etc/rc.conf.d/*; do
        [ -f "$conf" ] && . "$conf"
    done
}

run_rc_command() {
    service=$1
    command=$2

    if [ -f "/etc/rc.d/$service" ]; then
        "/etc/rc.d/$service" "$command"
    fi
}

start_daemon() {
    echo -n " Starting $1"
    $2
    echo "."
}
EOF
        chmod 644 /etc/rc.subr

        # rc.conf (configuration)
        cat > /etc/rc.conf << 'EOF'
# /etc/rc.conf - system configuration
hostname="lfs-desktop"
keymap="us"
EOF
        ;;
esac

# ====================================================================
# SERVICES COMMUNS (pour les deux styles)
# ====================================================================

# Service réseau
cat > /etc/rc.d/init.d/network << 'EOF'
#!/bin/bash
# Network service

. /etc/rc.d/init.d/functions

case "$1" in
    start)
        echo -n "Starting network..."
        ip link set lo up
        [ -d /sys/class/net/eth0 ] && {
            ip link set eth0 up
            [ -f /sbin/dhcpcd ] && dhcpcd eth0 2>/dev/null
        }
        evaluate_retval
        ;;
    stop)
        echo -n "Stopping network..."
        killall dhcpcd 2>/dev/null
        ip link set lo down
        evaluate_retval
        ;;
    restart)
        $0 stop
        sleep 1
        $0 start
        ;;
    status)
        ip link show lo
        [ -d /sys/class/net/eth0 ] && ip link show eth0
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
EOF
chmod 755 /etc/rc.d/init.d/network

# Fonctions communes
cat > /etc/rc.d/init.d/functions << 'EOF'
#!/bin/bash
# Common functions for init scripts

evaluate_retval() {
    if [ $? -eq 0 ]; then
        echo_success
    else
        echo_failure
    fi
    echo
}

echo_success() {
    echo -n " [  "
    echo -ne "\033[32mOK\033[0m"
    echo -n "  ]"
}

echo_failure() {
    echo -n " [ "
    echo -ne "\033[31mFAIL\033[0m"
    echo -n " ]"
}
EOF
chmod 644 /etc/rc.d/init.d/functions

# Activer les services par défaut
ln -sf ../init.d/network /etc/rc.d/rc3.d/S10network 2>/dev/null || true

log_success "SysVinit boot scripts configured"