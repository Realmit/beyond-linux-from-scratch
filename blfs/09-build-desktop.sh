#!/bin/bash
# Desktop environment (XFCE) – avec copie des binaires head/cut et dynamic source path
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

IN_DOCKER=false
if [ -f /.dockerenv ] || [ -f /run/.containerenv ] || grep -q docker /proc/1/cgroup 2>/dev/null; then
    IN_DOCKER=true
    log_info "Running in Docker container"
fi

if [ "$IN_DOCKER" = true ]; then
    LFS=${LFS:-/output/image}
else
    LFS=${LFS:-/mnt/lfs}
fi

if [ -z "$LFS" ]; then
    log_error "LFS variable not set"
    exit 1
fi

run_privileged() {
    if [ "$(whoami)" = "root" ]; then
        "$@"
    else
        sudo "$@"
    fi
}

log_info "========================================="
log_info "Setting up desktop environment (XFCE)"
log_info "========================================="

if [ "$IN_DOCKER" = true ]; then
    log_info "Docker mode – creating minimal desktop skeleton inside $LFS"
    run_privileged mkdir -pv "$LFS"/etc/X11/xorg.conf.d
    run_privileged mkdir -pv "$LFS"/etc/xdg/xfce4/xfconf/xfce-perchannel-xml
    run_privileged mkdir -pv "$LFS"/etc/xdg/autostart
    run_privileged mkdir -pv "$LFS"/usr/share/xfce4
    run_privileged mkdir -pv "$LFS"/usr/share/applications
    run_privileged tee "$LFS/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml" << 'SESSION'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-session" version="1.0">
  <property name="general" type="empty">
    <property name="FailsafeSession" type="string" value="Failsafe"/>
    <property name="SessionName" type="string" value="Default"/>
  </property>
</channel>
SESSION
    log_success "Desktop skeleton created (Docker mode)"
    exit 0
fi

log_info "Native mode – installing XFCE desktop from sources"

log_info "Copying head and cut into chroot"
for tool in head cut; do
    src=$(which "$tool" 2>/dev/null || echo "/usr/bin/$tool")
    if [ -f "$src" ]; then
        run_privileged cp -L -v "$src" "$LFS/usr/bin/" 2>/dev/null || true
        ldd "$src" 2>/dev/null | grep "=> /" | awk '{print $3}' | while read lib; do
            lib_dir="$LFS/lib"
            [[ "$lib" == *"/lib64/"* ]] && lib_dir="$LFS/lib64"
            run_privileged mkdir -p "$lib_dir"
            run_privileged cp -v "$lib" "$lib_dir/"
        done
    fi
done

if [ ! -f "$LFS/bin/bash" ]; then
    log_error "/bin/bash not found in $LFS/bin"
    exit 1
fi

run_privileged mount --bind /dev $LFS/dev 2>/dev/null || true
run_privileged mount -t devpts devpts $LFS/dev/pts 2>/dev/null || true
run_privileged mount -t proc proc $LFS/proc 2>/dev/null || true
run_privileged mount -t sysfs sysfs $LFS/sys 2>/dev/null || true
run_privileged mount -t tmpfs tmpfs $LFS/run 2>/dev/null || true

# --- DYNAMIC SOURCE PATH ---
SOURCES_HOST="$(dirname "$LFS")/sources"
if [ -d "$SOURCES_HOST" ] && [ "$(ls -A "$SOURCES_HOST" 2>/dev/null)" ]; then
    log_info "Copying sources from $SOURCES_HOST to $LFS/sources"
    run_privileged mkdir -p "$LFS/sources"
    run_privileged cp -rv "$SOURCES_HOST"/* "$LFS/sources/"
    run_privileged chown -R lfs:lfs "$LFS/sources"
fi

cat > "$LFS/build-xfce.sh" << 'INNEREOF'
#!/bin/bash
set -e
cd /sources

compile_package() {
    local pattern=$1
    local archive=$(ls -1 $pattern 2>/dev/null | head -n1)
    if [ -z "$archive" ]; then
        echo "WARNING: No source found for $pattern"
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

for pkg in "xfce4-*.tar.bz2" "xfce4-*.tar.xz" "gtk-*.tar.xz" "libxfce4util-*.tar.xz" "xfconf-*.tar.xz" "libxfce4ui-*.tar.xz"; do
    compile_package "$pkg" || true
done
echo "XFCE desktop installation complete."
INNEREOF

run_privileged chmod +x "$LFS/build-xfce.sh"
run_privileged chroot "$LFS" /bin/bash /build-xfce.sh

run_privileged umount $LFS/dev/pts 2>/dev/null || true
run_privileged umount $LFS/dev 2>/dev/null || true
run_privileged umount $LFS/proc 2>/dev/null || true
run_privileged umount $LFS/sys 2>/dev/null || true
run_privileged umount $LFS/run 2>/dev/null || true

log_success "XFCE desktop environment installed successfully"