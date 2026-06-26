#!/bin/bash
# Service Management Abstraction Layer
# Compatible with Docker and native Linux

set -e

# Functions
log_info() { echo "[INFO] $1"; }
log_warning() { echo "[WARNING] $1"; }
log_success() { echo "[SUCCESS] $1"; }

# Detect Docker
IN_DOCKER=false
if [ -f /.dockerenv ] || [ -f /run/.containerenv ] || grep -q docker /proc/1/cgroup 2>/dev/null; then
    IN_DOCKER=true
    log_info "Running in Docker container"
fi

# Set LFS and PREFIX
if [ "$IN_DOCKER" = true ]; then
    LFS=${LFS:-/output/image}
    PREFIX="$LFS"
else
    LFS=${LFS:-/mnt/lfs}
    PREFIX=""
fi

log_info "LFS: $LFS"
log_info "PREFIX: $PREFIX"

# Find init.conf - MULTIPLE PATHS
INIT_SYSTEM="sysvinit"
INIT_CONF_FOUND=false

# Try all possible paths
for path in "/lfs-builder/config/init.conf" "$SCRIPT_DIR/../config/init.conf" "$(pwd)/config/init.conf" "config/init.conf" "/config/init.conf"; do
    if [ -f "$path" ]; then
        log_info "Found init.conf at: $path"
        source "$path"
        INIT_CONF_FOUND=true
        break
    fi
done

if [ "$INIT_CONF_FOUND" = false ]; then
    log_warning "init.conf not found, using sysvinit"
    INIT_SYSTEM="sysvinit"
fi

log_info "Init system: $INIT_SYSTEM"

# Create directories
mkdir -pv $PREFIX/usr/local/bin
mkdir -pv $PREFIX/etc/profile.d
mkdir -pv $PREFIX/etc/init.d

# If in Docker - SIMPLE VERSION
if [ "$IN_DOCKER" = true ]; then
    log_info "Docker mode - creating minimal service wrapper"
    
    cat > $PREFIX/usr/local/bin/svc << 'DOCKER_SVC'
#!/bin/bash
echo "Service $2: $1 (Docker mode)"
exit 0
DOCKER_SVC
    chmod 755 $PREFIX/usr/local/bin/svc
    
    cat > $PREFIX/etc/profile.d/svc-aliases.sh << 'DOCKER_ALIAS'
alias sv-start='svc start'
alias sv-stop='svc stop'
alias sv-restart='svc restart'
alias sv-status='svc status'
DOCKER_ALIAS
    chmod 644 $PREFIX/etc/profile.d/svc-aliases.sh
    
    log_success "Service management configured for Docker"
    exit 0
fi

# Native mode - FULL VERSION
log_info "Native mode - installing full service management"

# Detect actual init
if [ -f /usr/lib/systemd/systemd ] && command -v systemctl >/dev/null 2>&1; then
    ACTUAL_INIT="systemd"
elif [ -f /sbin/init ] && strings /sbin/init 2>/dev/null | grep -q "sysvinit"; then
    ACTUAL_INIT="sysvinit"
elif [ -d /etc/rc.d/init.d ] && [ -f /etc/inittab ]; then
    ACTUAL_INIT="sysvinit"
else
    ACTUAL_INIT="$INIT_SYSTEM"
fi

log_info "Detected init system: $ACTUAL_INIT"

# Create svc command
cat > /usr/local/bin/svc << 'NATIVE_SVC'
#!/bin/bash
# Service management wrapper

# Detect init
if [ -f /usr/lib/systemd/systemd ] && command -v systemctl >/dev/null 2>&1; then
    INIT="systemd"
elif [ -f /sbin/init ] && strings /sbin/init 2>/dev/null | grep -q "sysvinit"; then
    INIT="sysvinit"
elif [ -d /etc/rc.d/init.d ] && [ -f /etc/inittab ]; then
    INIT="sysvinit"
else
    INIT="sysvinit"
fi

case "$INIT" in
    systemd)
        systemctl "$@"
        ;;
    sysvinit)
        SVC_DIR=""
        [ -d "/etc/rc.d/init.d" ] && SVC_DIR="/etc/rc.d/init.d"
        [ -d "/etc/init.d" ] && SVC_DIR="/etc/init.d"
        
        if [ -z "$SVC_DIR" ]; then
            echo "No service directory found"
            exit 1
        fi
        
        case "$1" in
            start|stop|restart|status)
                if [ -x "$SVC_DIR/$2" ]; then
                    "$SVC_DIR/$2" "$1"
                else
                    echo "Service $2 not found"
                    exit 1
                fi
                ;;
            *)
                echo "Usage: svc {start|stop|restart|status} service"
                ;;
        esac
        ;;
esac
NATIVE_SVC

chmod 755 /usr/local/bin/svc

# Aliases
cat > /etc/profile.d/svc-aliases.sh << 'NATIVE_ALIAS'
alias sv-start='svc start'
alias sv-stop='svc stop'
alias sv-restart='svc restart'
alias sv-status='svc status'
NATIVE_ALIAS
chmod 644 /etc/profile.d/svc-aliases.sh

log_success "Service management installed"
