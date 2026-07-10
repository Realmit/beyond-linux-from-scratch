#!/bin/bash
# Build BLFS base packages (minimal set)
# Author : Jean-Francois Landreville, landrevillejf@protonmail.com, 2026.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/../common/utils.sh" ]; then
    source "$SCRIPT_DIR/../common/utils.sh"
else
    log_info() { echo "[INFO] $*"; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_warning() { echo "[WARNING] $*"; }
    log_success() { echo "[SUCCESS] $*"; }
fi

LFS=${LFS:-/mnt/lfs}
KERNEL_TYPE=${KERNEL_TYPE:-linux}
export KERNEL_TYPE

if [ "$EUID" -ne 0 ]; then
    log_info "Relaunching with sudo..."
    exec sudo -E "$0" "$@"
fi

log_info "========================================="
log_info "Building BLFS base packages"
log_info "========================================="

if [ ! -d "$LFS" ]; then
    log_error "LFS directory $LFS does not exist"
    exit 1
fi

# Montages
mountpoint -q "$LFS/dev"  || mount --bind /dev "$LFS/dev"
mountpoint -q "$LFS/dev/pts" || mount -t devpts devpts "$LFS/dev/pts"
mountpoint -q "$LFS/proc" || mount -t proc proc "$LFS/proc"
mountpoint -q "$LFS/sys"  || mount -t sysfs sysfs "$LFS/sys"
mountpoint -q "$LFS/run"  || mount -t tmpfs tmpfs "$LFS/run"

cleanup() {
    umount "$LFS/dev/pts" 2>/dev/null || true
    umount "$LFS/dev" 2>/dev/null || true
    umount "$LFS/proc" 2>/dev/null || true
    umount "$LFS/sys" 2>/dev/null || true
    umount "$LFS/run" 2>/dev/null || true
}
trap cleanup EXIT

# Copie des sources si nécessaire
SOURCES_HOST="$(dirname "$LFS")/sources"
if [ -d "$SOURCES_HOST" ] && [ "$(ls -A "$SOURCES_HOST" 2>/dev/null)" ]; then
    log_info "Copying sources from $SOURCES_HOST to $LFS/sources"
    mkdir -p "$LFS/sources"
    cp -rv "$SOURCES_HOST"/* "$LFS/sources/"
    chown -R lfs:lfs "$LFS/sources" 2>/dev/null || true
fi

# Script de compilation BLFS
cat > "$LFS/build-blfs-base.sh" << 'INNEREOF'
#!/bin/bash
set -e
cd /sources

compile_package() {
    local archive=$1
    if [ ! -f "$archive" ]; then
        echo "WARNING: No source found for $archive"
        return 1
    fi
    local dir=$(tar -tf "$archive" | head -1 | cut -d/ -f1)
    echo "=== Building $dir ==="
    tar -xf "$archive"
    cd "$dir"
    if [ -f "configure" ]; then
        ./configure --prefix=/usr --sysconfdir=/etc
    elif [ -f "Makefile" ]; then
        true
    fi
    make -j$(nproc)
    make install
    cd /sources
    rm -rf "$dir"
    echo "=== $dir done ==="
}

for pattern in curl-*.tar.xz openssl-*.tar.gz expat-*.tar.xz libxml2-*.tar.xz; do
    for archive in $pattern; do
        if [ -f "$archive" ]; then
            compile_package "$archive" || true
            break
        fi
    done
done

echo "BLFS base packages built."
INNEREOF

chmod +x "$LFS/build-blfs-base.sh"

# Exécution dans le chroot
run_privileged env -i HOME=/root TERM="$TERM" PS1='(lfs chroot) \u:\w\$ ' PATH=/bin:/usr/bin:/sbin:/usr/sbin chroot "$LFS" /bin/bash -c "export PATH=/bin:/usr/bin:/sbin:/usr/sbin; export KERNEL_TYPE=$KERNEL_TYPE; /build-blfs-base.sh"

log_success "BLFS base packages built successfully"