#!/bin/bash
# Init System Installation
# Supports: sysvinit (traditional) and systemd (modern)

set -e

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[0;34m[SUCCESS]\033[0m $1"; }

INIT_SYSTEM="${INIT_SYSTEM:-sysvinit}"
SYSVINIT_STYLE="${SYSVINIT_STYLE:-lfs-classic}"

log_info "Installing init system: $INIT_SYSTEM"

case "$INIT_SYSTEM" in
    sysvinit|sysv|sysv-init)
        # ====================================================================
        # SYSVINIT - Traditional UNIX init
        # ====================================================================
        log_info "Installing sysvinit 3.14 (traditional UNIX init)"

        cd /sources
        if [ -f sysvinit-3.14.tar.xz ]; then
            tar -xf sysvinit-3.14.tar.xz
            cd sysvinit-3.14
            make -C src
            make -C src install
            cd ..
            log_success "sysvinit installed"
        else
            log_warning "sysvinit source not found"
        fi

        # Créer /etc/inittab de base
        cat > /etc/inittab << "EOF"
# /etc/inittab - Base configuration

# Default runlevel (3 = multi-user without X)
id:3:initdefault:

# System initialization
si::sysinit:/etc/rc.d/init.d/rc S

# Runlevels
l0:0:wait:/etc/rc.d/init.d/rc 0
l1:1:wait:/etc/rc.d/init.d/rc 1
l2:2:wait:/etc/rc.d/init.d/rc 2
l3:3:wait:/etc/rc.d/init.d/rc 3
l4:4:wait:/etc/rc.d/init.d/rc 4
l5:5:wait:/etc/rc.d/init.d/rc 5
l6:6:wait:/etc/rc.d/init.d/rc 6

# Ctrl-Alt-Delete
ca::ctrlaltdel:/sbin/shutdown -t5 -r now

# Virtual terminals
1:2345:respawn:/sbin/agetty --noclear tty1 38400
2:2345:respawn:/sbin/agetty tty2 38400
3:2345:respawn:/sbin/agetty tty3 38400
4:2345:respawn:/sbin/agetty tty4 38400
5:2345:respawn:/sbin/agetty tty5 38400
6:2345:respawn:/sbin/agetty tty6 38400
EOF
        ;;

    systemd)
        # ====================================================================
        # SYSTEMD - Modern init
        # ====================================================================
        log_info "Installing systemd 259.1 (modern init)"

        cd /sources
        if [ -f systemd-259.1.tar.gz ]; then
            tar -xf systemd-259.1.tar.gz
            cd systemd-259.1

            # Patch pour LFS
            sed -i 's/GROUP="render"/GROUP="video"/' rules.d/50-udev-default.rules.in

            mkdir -p build
            cd build
            meson setup .. \
                --prefix=/usr \
                --buildtype=release \
                -Ddefault-dnssec=no \
                -Dfirstboot=false \
                -Dinstall-tests=false \
                -Dldconfig=false \
                -Dsysusers=false \
                -Drpmmacrosdir=no \
                -Dhomed=false \
                -Duserdb=false \
                -Dman=false \
                -Dmode=release \
                -Dsystemd-analyze=true \
                -Dsystemd-journal-upload=true

            meson compile
            meson install
            cd ../..

            # Créer machine-id
            systemd-machine-id-setup 2>/dev/null || true

            log_success "systemd installed"
        else
            log_warning "systemd source not found"
        fi
        ;;

    *)
        log_warning "Unknown init system: $INIT_SYSTEM, using sysvinit"
        ;;
esac

log_success "Init system installation complete"