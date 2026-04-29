#!/bin/bash
# Common utility functions for LFS build scripts

set -e

LFS=${LFS:-/mnt/lfs}
LFS_TGT=${LFS_TGT:-x86_64-lfs-linux-gnu}
NUM_JOBS=${NUM_JOBS:-$(nproc)}
LC_ALL=POSIX

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Mount virtual filesystems
mount_virtual_kernel_filesystems() {
    log_info "Mounting virtual kernel filesystems"

    mount -v --bind /dev $LFS/dev
    mount -v --bind /dev/pts $LFS/dev/pts
    mount -vt proc proc $LFS/proc
    mount -vt sysfs sysfs $LFS/sys
    mount -vt tmpfs tmpfs $LFS/run

    if [ -h $LFS/dev/shm ]; then
        mkdir -pv $LFS/$(readlink $LFS/dev/shm)
    fi
}

# Unmount virtual filesystems
umount_virtual_kernel_filesystems() {
    log_info "Unmounting virtual kernel filesystems"

    umount -v $LFS/dev/pts
    umount -v $LFS/dev
    umount -v $LFS/proc
    umount -v $LFS/sys
    umount -v $LFS/run
}

# Enter chroot environment
enter_chroot() {
    log_info "Entering chroot environment"

    chroot "$LFS" /usr/bin/env -i   \
        HOME=/root                  \
        TERM="$TERM"                \
        PS1='(lfs chroot) \u:\w\$ ' \
        PATH=/usr/bin:/usr/sbin     \
        /bin/bash --login +h
}

# Build with logging
build_package() {
    local pkg_name=$1
    local build_cmd=${2:-"make -j$NUM_JOBS"}

    log_info "Building $pkg_name"

    if [ -f "/sources/$pkg_name/build.log" ]; then
        rm "/sources/$pkg_name/build.log"
    fi

    pushd "/sources/$pkg_name"

    if ! eval "$build_cmd" > build.log 2>&1; then
        log_error "Failed to build $pkg_name. Check build.log"
        popd
        return 1
    fi

    popd
    log_info "Successfully built $pkg_name"
    return 0
}

# Download file if not exists
download_file() {
    local url=$1
    local dest=$2

    if [ ! -f "$dest" ]; then
        log_info "Downloading $dest"
        wget -c "$url" -O "$dest"
    else
        log_info "$dest already exists, skipping download"
    fi
}

# Verify checksum
verify_checksum() {
    local file=$1
    local expected_md5=$2

    local actual_md5=$(md5sum "$file" | cut -d' ' -f1)

    if [ "$actual_md5" != "$expected_md5" ]; then
        log_error "Checksum mismatch for $file"
        log_error "Expected: $expected_md5"
        log_error "Actual: $actual_md5"
        return 1
    fi

    log_info "Checksum verified for $file"
    return 0
}

# Extract archive
extract_archive() {
    local archive=$1
    local dest=${2:-$(pwd)}

    case "$archive" in
        *.tar.gz|*.tgz) tar -xzf "$archive" -C "$dest" ;;
        *.tar.bz2)      tar -xjf "$archive" -C "$dest" ;;
        *.tar.xz)       tar -xJf "$archive" -C "$dest" ;;
        *.zip)          unzip "$archive" -d "$dest" ;;
        *)              log_error "Unknown archive format: $archive"; return 1 ;;
    esac
}

# Create system user
create_system_user() {
    local username=$1
    local groups=${2:-users}

    if ! id "$username" &>/dev/null; then
        groupadd -g 1000 "$username"
        useradd -c "LFS User" -d "/home/$username" -u 1000 -g 1000 -G "$groups" -m "$username"
        log_info "Created user: $username"
    else
        log_warning "User $username already exists"
    fi
}

# Update environment profile
update_environment() {
    cat >> /etc/profile << "EOF"
# LFS Environment
export LFS=$LFS
export LFS_TGT=$LFS_TGT
export PATH=/usr/local/bin:$PATH
export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH
export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH

# Custom prompt for LFS
if [ -n "$LFS" ]; then
    PS1='(lfs) \u:\w\$ '
fi
EOF

    log_info "Environment profile updated"
}

# Create backup
create_backup() {
    local source=$1
    local backup_name=$2
    local timestamp=$(date +%Y%m%d_%H%M%S)

    if [ -e "$source" ]; then
        tar -czf "/backups/${backup_name}_${timestamp}.tar.gz" "$source"
        log_info "Backup created: ${backup_name}_${timestamp}.tar.gz"
    fi
}