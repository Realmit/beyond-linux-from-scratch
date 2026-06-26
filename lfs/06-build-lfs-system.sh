#!/bin/bash
# Build complete LFS system with init system choice
# Orchestrates all 6 init-related scripts - Compatible with Docker and native

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fallback functions if utils.sh doesn't exist
if [ -f "$SCRIPT_DIR/../common/utils.sh" ]; then
    source "$SCRIPT_DIR/../common/utils.sh"
else
    log_info() { echo "[INFO] $*"; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_warning() { echo "[WARNING] $*"; }
    log_success() { echo "[SUCCESS] $*"; }
fi

# Detect if running in Docker
IN_DOCKER=false
if [ -f /.dockerenv ] || [ -f /run/.containerenv ] || grep -q docker /proc/1/cgroup 2>/dev/null; then
    IN_DOCKER=true
    log_info "Running in Docker container"
fi

# Detect if running in Lima VM
IN_LIMA=false
if [ -f /etc/lima-version ]; then
    IN_LIMA=true
    log_info "Running in Lima VM"
fi

# Set LFS directory
if [ "$IN_DOCKER" = true ]; then
    LFS=${LFS:-/output/image}
else
    LFS=${LFS:-/mnt/lfs}
fi

if [ -z "$LFS" ]; then
    log_error "LFS variable not set"
    exit 1
fi

log_info "========================================="
log_info "Building LFS System with Init System Choice"
log_info "========================================="

# Find init.conf - works in Docker and native
INIT_CONF=""
possible_paths=(
    "/lfs-builder/config/init.conf"
    "$SCRIPT_DIR/../config/init.conf"
    "$(pwd)/config/init.conf"
    "config/init.conf"
    "/config/init.conf"
)

for path in "${possible_paths[@]}"; do
    if [ -f "$path" ]; then
        INIT_CONF="$path"
        break
    fi
done

# Load init system configuration
if [ -n "$INIT_CONF" ]; then
    log_info "Loading init system config from: $INIT_CONF"
    source "$INIT_CONF"
else
    log_warning "config/init.conf not found, using defaults"
    INIT_SYSTEM="${INIT_SYSTEM:-sysvinit}"
    SYSVINIT_STYLE="${SYSVINIT_STYLE:-lfs-classic}"
    PARALLEL_STARTUP="${PARALLEL_STARTUP:-false}"
    AUTO_RESTART="${AUTO_RESTART:-true}"
    DEFAULT_RUNLEVEL="${DEFAULT_RUNLEVEL:-3}"
    SERVICE_TIMEOUT="${SERVICE_TIMEOUT:-5}"
    MAX_PARALLEL="${MAX_PARALLEL:-1}"
fi

log_info "Init system selected: $INIT_SYSTEM"

# If in Docker, create minimal system and exit
if [ "$IN_DOCKER" = true ] || [ "$IN_LIMA" = true ]; then
    log_info "Running in Docker/Lima mode - creating minimal system"
    
    # Create basic directories
    mkdir -pv $LFS/{bin,boot,dev,etc,home,lib,lib64,media,mnt,opt,proc,root,run,sbin,srv,sys,tmp,usr,var}
    mkdir -pv $LFS/usr/{bin,include,lib,lib64,sbin,share,src}
    mkdir -pv $LFS/var/{cache,lib,local,lock,log,opt,run,spool,tmp}
    mkdir -pv $LFS/etc/{profile.d,sysconfig,skel,init.d,rc.d,systemd}
    
    # Create init scripts
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

    # Copy essential binaries
    for tool in bash sh ls cp mv mkdir rm cat echo grep sed; do
        if [ -f "/bin/$tool" ] && [ ! -f "$LFS/bin/$tool" ]; then
            cp -v /bin/$tool $LFS/bin/ 2>/dev/null || true
        fi
    done

    # Create dev files
    if [ ! -e $LFS/dev/null ]; then
        mknod -m 0666 $LFS/dev/null c 1 3 2>/dev/null || true
    fi
    if [ ! -e $LFS/dev/zero ]; then
        mknod -m 0666 $LFS/dev/zero c 1 5 2>/dev/null || true
    fi

    # Create profile
    cat > $LFS/etc/profile << 'PROFILE'
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export PATH=/usr/local/bin:/usr/bin:/bin
export PS1='\u@\h \w\$ '
PROFILE

    log_success "Minimal LFS system created in Docker"
    exit 0
fi

# Native mode - full system build
log_info "Running in native mode - full system build"

# Mount virtual filesystems
log_info "Mounting virtual filesystems"
mount -v --bind /dev $LFS/dev 2>/dev/null || true
mount -vt devpts devpts $LFS/dev/pts 2>/dev/null || true
mount -vt proc proc $LFS/proc 2>/dev/null || true
mount -vt sysfs sysfs $LFS/sys 2>/dev/null || true
mount -vt tmpfs tmpfs $LFS/run 2>/dev/null || true

# Copy init scripts to chroot
log_info "Copying init scripts to chroot"
for script in 06a-init-system.sh 06b-service-management.sh; do
    if [ -f "$SCRIPT_DIR/$script" ]; then
        cp "$SCRIPT_DIR/$script" "$LFS/init-$script"
        chmod +x "$LFS/init-$script"
    fi
done

# Create build script
cat > "$LFS/build-system.sh" << 'INNEREOF'
#!/bin/bash
set -e

# Colors
log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[0;34m[SUCCESS]\033[0m $1"; }
log_warning() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }

export INIT_SYSTEM="$INIT_SYSTEM"
export SYSVINIT_STYLE="$SYSVINIT_STYLE"

cd /sources || exit 1

# Build system packages
log_info "Building system packages..."

# Function to build a package
build_package() {
    local pkg=$1
    local config_args=$2
    
    if ls ${pkg}-*.tar.* 2>/dev/null | head -n1 > /dev/null; then
        log_info "Building $pkg..."
        tar -xf ${pkg}-*.tar.*
        cd ${pkg}-*
        if [ -f "configure" ]; then
            ./configure $config_args --prefix=/usr
            make -j$(nproc)
            make install
        elif [ -f "meson.build" ]; then
            meson setup build
            meson compile -C build
            meson install -C build
        elif [ -f "Makefile" ] || [ -f "makefile" ]; then
            make -j$(nproc)
            make install
        fi
        cd /sources
        rm -rf ${pkg}-*
    fi
}

# Build essential packages
build_package "linux-api-headers" ""
build_package "man-pages" ""
build_package "glibc" ""
build_package "zlib" ""
build_package "binutils" ""
build_package "gcc" ""
build_package "gmp" ""
build_package "mpfr" ""
build_package "mpc" ""

# Install init system
log_info "Installing init system: $INIT_SYSTEM"
if [ -f "/init-06a-init-system.sh" ]; then
    /bin/bash /init-06a-init-system.sh
fi

# Service management
if [ -f "/init-06b-service-management.sh" ]; then
    /bin/bash /init-06b-service-management.sh
fi

# System configuration
log_info "Configuring system"

cat > /etc/fstab << "FSTAB"
# /etc/fstab
/dev/sda3      /            ext4    defaults            1     1
/dev/sda1      /boot        vfat    defaults            0     2
/dev/sda2      swap         swap    pri=1               0     0
proc           /proc        proc    nosuid,noexec,nodev 0     0
sysfs          /sys         sysfs   nosuid,noexec,nodev 0     0
devpts         /dev/pts     devpts  gid=5,mode=620      0     0
tmpfs          /run         tmpfs   defaults            0     0
devtmpfs       /dev         devtmpfs mode=0755,nosuid   0     0
tmpfs          /dev/shm     tmpfs   nosuid,nodev        0     0
FSTAB

echo "lfs-desktop" > /etc/hostname

cat > /etc/hosts << "HOSTS"
127.0.0.1   localhost.localdomain localhost
::1         localhost ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
127.0.1.1   lfs-desktop
HOSTS

ln -sfv /usr/share/zoneinfo/UTC /etc/localtime

cat > /etc/locale.conf << "LOCALE"
LANG=en_US.UTF-8
LOCALE

cat > /etc/vconsole.conf << "VCONSOLE"
KEYMAP=us
FONT=Lat2-Terminus16
VCONSOLE

log_success "LFS system build complete!"
INNEREOF

chmod +x "$LFS/build-system.sh"

# Run chroot build
log_info "Running system build in chroot"
chroot "$LFS" /usr/bin/env -i \
    HOME=/root \
    TERM="$TERM" \
    PS1='(lfs chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin:/bin \
    INIT_SYSTEM="$INIT_SYSTEM" \
    SYSVINIT_STYLE="$SYSVINIT_STYLE" \
    /bin/bash /build-system.sh

# Cleanup
log_info "Cleaning up"
rm -f "$LFS"/init-*.sh "$LFS"/build-system.sh

umount -v $LFS/dev/pts 2>/dev/null || true
umount -v $LFS/dev 2>/dev/null || true
umount -v $LFS/proc 2>/dev/null || true
umount -v $LFS/sys 2>/dev/null || true
umount -v $LFS/run 2>/dev/null || true

log_success "LFS system build complete!"
