#!/bin/bash
# Init System Selection and Setup
# Run inside chroot environment

set -e

# Vérifier si on est dans Docker
IN_DOCKER=0
if [ -f /.dockerenv ]; then
    IN_DOCKER=1
    echo "Running in Docker container - adapting init system setup"
fi

source /etc/lfs-build.conf 2>/dev/null || source /etc/profile.d/lfs.sh 2>/dev/null || true

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[0;34m[SUCCESS]\033[0m $1"; }
log_warning() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }

INIT_SYSTEM="${INIT_SYSTEM:-systemd}"
SERVICE_STYLE="${SERVICE_STYLE:-classic}"

log_info "Setting up init system: $INIT_SYSTEM"

# Créer les répertoires nécessaires (même dans Docker)
mkdir -p /etc/systemd/system/getty@tty1.service.d 2>/dev/null || true
mkdir -p /etc/rc.d/{init.d,rc0.d,rc1.d,rc2.d,rc3.d,rc4.d,rc5.d,rc6.d} 2>/dev/null || true
mkdir -p /etc/init.d 2>/dev/null || true
mkdir -p /etc/runit/runsvdir/default 2>/dev/null || true
mkdir -p /etc/s6/servicedb 2>/dev/null || true

###############################################################################
# SYSTEMD (Modern)
###############################################################################
setup_systemd() {
    log_info "Configuring systemd"

    # Install systemd if not present (et pas dans Docker où c'est déjà installé)
    if [ ! -f /usr/lib/systemd/systemd ] && [ $IN_DOCKER -eq 0 ]; then
        log_info "Installing systemd..."
        cd /sources
        if [ -f systemd-*.tar.gz ]; then
            tar -xf systemd-*.tar.gz
            cd systemd-*
            mkdir -p build
            cd build
            meson setup --prefix=/usr --buildtype=release \
                -Ddefault-dnssec=no \
                -Dfirstboot=false \
                -Dinstall-tests=false \
                -Dldconfig=false \
                -Dsysusers=false \
                -Drpmmacrosdir=no \
                -Dhomed=false \
                -Duserdb=false \
                -Dman=false \
                -Dmode=release ..
            meson compile
            meson install
            cd ../..
        else
            log_warning "systemd source not found, skipping installation"
        fi
    elif [ $IN_DOCKER -eq 1 ]; then
        log_warning "Running in Docker - using existing systemd"
    fi

    # Create basic service files (toujours, même dans Docker)
    cat > /etc/systemd/system/getty@tty1.service.d/override.conf << 'EOF' 2>/dev/null || true
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -- \\u' --noclear -a lfsuser %I $TERM
Restart=always
RestartSec=0
EOF

    # Set default target based on desktop (si systemctl existe)
    if command -v systemctl >/dev/null 2>&1; then
        if [ -f /usr/bin/startx ] || [ -f /usr/bin/xinit ]; then
            systemctl set-default graphical.target 2>/dev/null || true
        else
            systemctl set-default multi-user.target 2>/dev/null || true
        fi
    else
        log_warning "systemctl not available"
    fi

    log_success "systemd configured"
}

###############################################################################
# SYSV INIT (Traditional)
###############################################################################
setup_sysvinit() {
    log_info "Configuring SysV init (classic style)"

    # Install SysV init si nécessaire
    if [ ! -f /sbin/init ] && [ $IN_DOCKER -eq 0 ]; then
        cd /sources
        if [ -f sysvinit-*.tar.xz ]; then
            tar -xf sysvinit-*.tar.xz
            cd sysvinit-*
            make -j$(nproc)
            make install
            cd ..
        fi
    fi

    # Create /etc/inittab
    cat > /etc/inittab << 'EOF'
# /etc/inittab

id:3:initdefault:

si::sysinit:/etc/rc.d/init.d/rc sysinit

l0:0:wait:/etc/rc.d/init.d/rc 0
l1:1:wait:/etc/rc.d/init.d/rc 1
l2:2:wait:/etc/rc.d/init.d/rc 2
l3:3:wait:/etc/rc.d/init.d/rc 3
l4:4:wait:/etc/rc.d/init.d/rc 4
l5:5:wait:/etc/rc.d/init.d/rc 5
l6:6:wait:/etc/rc.d/init.d/rc 6

ca:12345:ctrlaltdel:/sbin/shutdown -t1 -a -r now now

1:2345:respawn:/sbin/agetty --noclear tty1 linux
2:2345:respawn:/sbin/agetty tty2 linux
3:2345:respawn:/sbin/agetty tty3 linux
4:2345:respawn:/sbin/agetty tty4 linux
5:2345:respawn:/sbin/agetty tty5 linux
6:2345:respawn:/sbin/agetty tty6 linux

EOF

    # Create main rc script
    cat > /etc/rc.d/rc << 'EOF'
#!/bin/bash

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
    chmod +x /etc/rc.d/rc

    # Create functions
    cat > /etc/rc.d/init.d/functions << 'EOF'
#!/bin/bash
success() { echo -e "  [ \033[32mOK\033[0m ]"; }
failure() { echo -e "  [ \033[31mFAIL\033[0m ]"; }
daemon() { $@ & echo $! > /var/run/$1.pid; }
EOF

    # Create network service
    cat > /etc/rc.d/init.d/network << 'EOF'
#!/bin/bash
. /etc/rc.d/init.d/functions
case "$1" in
    start) echo -n "Starting network..."; ip link set lo up; success ;;
    stop) echo -n "Stopping network..."; ip link set lo down; success ;;
    restart) $0 stop; $0 start ;;
    status) ip link show lo ;;
    *) echo "Usage: $0 {start|stop|restart|status}"; exit 1 ;;
esac
EOF
    chmod +x /etc/rc.d/init.d/network

    # Create symlink
    ln -sf ../init.d/network /etc/rc.d/rc3.d/S10network 2>/dev/null || true

    log_success "SysV init configured"
}

###############################################################################
# OPENRC (Gentoo style)
###############################################################################
setup_openrc() {
    log_info "Configuring OpenRC (dependency-based init)"

    if [ $IN_DOCKER -eq 0 ] && [ -f /sources/openrc-*.tar.gz ]; then
        cd /sources
        tar -xf openrc-*.tar.gz
        cd openrc-*

        cat > /etc/rc.conf << 'EOF'
rc_sys=""
rc_env_allow=".*"
rc_logger="YES"
rc_parallel="YES"
rc_interactive="NO"
EOF

        make -j$(nproc)
        make install
        cd ..
    fi

    # Create service
    cat > /etc/init.d/net.lo << 'EOF'
#!/sbin/openrc-run
depend() { need localmount; before net; }
start() { ebegin "Starting loopback"; ip link set lo up; eend $?; }
stop() { ebegin "Stopping loopback"; ip link set lo down; eend $?; }
EOF
    chmod +x /etc/init.d/net.lo

    if command -v rc-update >/dev/null 2>&1; then
        rc-update add net.lo boot 2>/dev/null || true
    fi

    log_success "OpenRC configured"
}

###############################################################################
# RUNIT (Simple supervision)
###############################################################################
setup_runit() {
    log_info "Configuring runit (simple supervision)"

    if [ $IN_DOCKER -eq 0 ] && [ -f /sources/runit-*.tar.gz ]; then
        cd /sources
        tar -xf runit-*.tar.gz
        cd runit-*
        ./package/compile
        cp command/* /usr/bin/
    fi

    # Create getty service
    mkdir -p /etc/runit/runsvdir/default/getty-tty1
    cat > /etc/runit/runsvdir/default/getty-tty1/run << 'EOF'
#!/bin/sh
exec /sbin/agetty --noclear tty1 linux
EOF
    chmod +x /etc/runit/runsvdir/default/getty-tty1/run

    log_success "runit configured"
}

###############################################################################
# S6 (Small supervision suite)
###############################################################################
setup_s6() {
    log_info "Configuring s6 (small supervision suite)"

    if [ $IN_DOCKER -eq 0 ] && [ -f /sources/s6-*.tar.gz ]; then
        cd /sources
        tar -xf s6-*.tar.gz
        cd s6-*
        ./configure --prefix=/usr
        make -j$(nproc)
        make install
    fi

    # Create getty service
    mkdir -p /etc/s6/servicedb/getty-tty1
    cat > /etc/s6/servicedb/getty-tty1/run << 'EOF'
#!/command/execlineb -P
/bin/agetty --noclear tty1 linux
EOF
    chmod +x /etc/s6/servicedb/getty-tty1/run

    log_success "s6 configured"
}

###############################################################################
# CORE SERVICE SCRIPTS (Common for all init systems)
###############################################################################
create_core_services() {
    log_info "Creating core service scripts"

    mkdir -p /usr/local/sbin

    # Network service
    cat > /usr/local/sbin/network-service << 'EOF'
#!/bin/bash
case "$1" in
    start) ip link set lo up; [ -d /sys/class/net/eth0 ] && { ip link set eth0 up; dhcpcd eth0 2>/dev/null || udhcpc -i eth0 2>/dev/null; } ;;
    stop) ip link set lo down; killall dhcpcd 2>/dev/null || killall udhcpc 2>/dev/null ;;
    restart) $0 stop; sleep 1; $0 start ;;
esac
EOF
    chmod +x /usr/local/sbin/network-service

    # SSH service
    if [ -f /usr/sbin/sshd ]; then
        cat > /usr/local/sbin/ssh-service << 'EOF'
#!/bin/bash
case "$1" in
    start) [ ! -f /var/run/sshd.pid ] && /usr/sbin/sshd ;;
    stop) [ -f /var/run/sshd.pid ] && kill $(cat /var/run/sshd.pid) && rm -f /var/run/sshd.pid ;;
    restart) $0 stop; sleep 1; $0 start ;;
esac
EOF
        chmod +x /usr/local/sbin/ssh-service
    fi

    # Cron service
    if [ -f /usr/sbin/crond ]; then
        cat > /usr/local/sbin/cron-service << 'EOF'
#!/bin/bash
case "$1" in
    start) /usr/sbin/crond ;;
    stop) killall crond 2>/dev/null ;;
    restart) $0 stop; sleep 1; $0 start ;;
esac
EOF
        chmod +x /usr/local/sbin/cron-service
    fi
}

###############################################################################
# MAIN
###############################################################################
main() {
    case "$INIT_SYSTEM" in
        systemd) setup_systemd ;;
        sysv) setup_sysvinit ;;
        openrc) setup_openrc ;;
        runit) setup_runit ;;
        s6) setup_s6 ;;
        *) log_warning "Unknown init system: $INIT_SYSTEM, using systemd"; setup_systemd ;;
    esac

    create_core_services

    if [ "$SERVICE_STYLE" = "supervision" ]; then
        log_info "Enabling automatic service supervision"
        if [ "$INIT_SYSTEM" = "runit" ] || [ "$INIT_SYSTEM" = "s6" ]; then
            log_info "Supervision already configured"
        else
            log_warning "Supervision style requires runit or s6 init"
        fi
    fi

    log_success "Init system $INIT_SYSTEM configured successfully"
}

main "$@"