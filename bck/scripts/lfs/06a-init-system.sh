#!/bin/bash
# Install init system - Compatible with Docker and native

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fallback functions
if [ -f "$SCRIPT_DIR/../common/utils.sh" ]; then
    source "$SCRIPT_DIR/../common/utils.sh"
else
    log_info() { echo "[INFO] $*"; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_warning() { echo "[WARNING] $*"; }
    log_success() { echo "[SUCCESS] $*"; }
fi

# Detect Docker
IN_DOCKER=false
if [ -f /.dockerenv ] || [ -f /run/.containerenv ] || grep -q docker /proc/1/cgroup 2>/dev/null; then
    IN_DOCKER=true
    log_info "Running in Docker container"
fi

# Set LFS
if [ "$IN_DOCKER" = true ]; then
    LFS=${LFS:-/output/image}
else
    LFS=${LFS:-/mnt/lfs}
fi

log_info "========================================="
log_info "Installing init system"
log_info "========================================="

# IMPORTANT: Chercher init.conf au bon endroit
INIT_CONF=""
if [ "$IN_DOCKER" = true ]; then
    # En Docker, le fichier est dans /lfs-builder/config/
    if [ -f "/lfs-builder/config/init.conf" ]; then
        INIT_CONF="/lfs-builder/config/init.conf"
        log_info "Found init.conf at: $INIT_CONF"
    fi
else
    # En natif, chercher dans le répertoire courant
    if [ -f "config/init.conf" ]; then
        INIT_CONF="config/init.conf"
        log_info "Found init.conf at: $INIT_CONF"
    fi
fi

# Si trouvé, charger
if [ -n "$INIT_CONF" ]; then
    log_info "Loading init system config from: $INIT_CONF"
    source "$INIT_CONF"
else
    log_warning "init.conf not found, using sysvinit as default"
    INIT_SYSTEM="sysvinit"
fi

log_info "Init system selected: $INIT_SYSTEM"

# Si en Docker, ne pas compiler, juste créer les scripts
if [ "$IN_DOCKER" = true ]; then
    log_info "Running in Docker mode - creating minimal init system"
    
    mkdir -pv $LFS/etc/init.d
    mkdir -pv $LFS/etc/rc.d
    
    cat > $LFS/etc/inittab << 'INITTAB'
id:3:initdefault:
si::sysinit:/etc/init.d/rcS
l0:0:wait:/etc/init.d/rc 0
l1:1:wait:/etc/init.d/rc 1
l2:2:wait:/etc/init.d/rc 2
l3:3:wait:/etc/init.d/rc 3
l4:4:wait:/etc/init.d/rc 4
l5:5:wait:/etc/init.d/rc 5
l6:6:wait:/etc/init.d/rc 6
ca::ctrlaltdel:/sbin/shutdown -t3 -r now
pf::powerfail:/sbin/shutdown -f -h +2 "Power Failure; System Shutting Down"
INITTAB

    cat > $LFS/etc/init.d/rcS << 'RCS'
#!/bin/sh
echo "Starting system..."
mount -o remount,rw /
mount -a
echo "System started."
RCS
    chmod +x $LFS/etc/init.d/rcS

    cat > $LFS/etc/init.d/rc << 'RC'
#!/bin/sh
echo "Runlevel $1"
RC
    chmod +x $LFS/etc/init.d/rc
    
    log_success "Init system (sysvinit) configured in Docker"
    exit 0
fi

# Mode natif - build from sources
log_info "Building init system from sources"

if [ ! -d "$LFS/sources" ]; then
    log_error "Sources directory not found: $LFS/sources"
    exit 1
fi

cd "$LFS/sources" || exit 1

case "$INIT_SYSTEM" in
    sysvinit|sysv)
        log_info "Installing sysvinit"
        if ls sysvinit-*.tar.xz 1>/dev/null 2>&1; then
            tar -xf sysvinit-*.tar.xz
            cd sysvinit-*
            make -j$(nproc)
            make install
            cd ..
            rm -rf sysvinit-*
            log_success "sysvinit installed"
        else
            log_warning "sysvinit source not found"
        fi
        ;;
    systemd)
        log_info "Installing systemd"
        if ls systemd-*.tar.gz 1>/dev/null 2>&1; then
            tar -xf systemd-*.tar.gz
            cd systemd-*
            meson setup build
            meson compile -C build
            meson install -C build
            cd ..
            rm -rf systemd-*
            log_success "systemd installed"
        else
            log_warning "systemd source not found"
        fi
        ;;
    *)
        log_warning "Unknown init system: $INIT_SYSTEM, using sysvinit"
        ;;
esac

log_success "Init system setup complete!"
