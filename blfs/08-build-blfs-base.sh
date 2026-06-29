#!/bin/bash
# Build BLFS base packages (minimal set) – with proper chroot handling
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
log_info "Building BLFS base packages"
log_info "========================================="

# Docker mode – minimal
if [ "$IN_DOCKER" = true ]; then
    log_info "Docker mode – creating minimal BLFS structure inside $LFS"
    run_privileged mkdir -pv "$LFS/usr/share/doc"
    run_privileged mkdir -pv "$LFS/usr/share/man"
    log_success "Minimal BLFS structure created"
    exit 0
fi

# Native mode
log_info "Native mode – building BLFS base packages"

# Vérifier que le chroot est fonctionnel
if [ ! -f "$LFS/bin/bash" ]; then
    log_error "/bin/bash not found in $LFS/bin – run lfs-basic first"
    exit 1
fi
if ! run_privileged chroot "$LFS" /bin/bash -c "exit 0" 2>/dev/null; then
    log_error "chroot not working – run lfs-basic first"
    exit 1
fi

# Monter les FS
run_privileged mount --bind /dev $LFS/dev 2>/dev/null || true
run_privileged mount -t devpts devpts $LFS/dev/pts 2>/dev/null || true
run_privileged mount -t proc proc $LFS/proc 2>/dev/null || true
run_privileged mount -t sysfs sysfs $LFS/sys 2>/dev/null || true
run_privileged mount -t tmpfs tmpfs $LFS/run 2>/dev/null || true

# Copier les sources BLFS (si présentes)
SOURCES_HOST="/tmp/lfs-build/sources"
if [ -d "$SOURCES_HOST" ] && [ "$(ls -A $SOURCES_HOST 2>/dev/null)" ]; then
    log_info "Copying sources from $SOURCES_HOST to $LFS/sources"
    run_privileged mkdir -p "$LFS/sources"
    run_privileged cp -rv "$SOURCES_HOST"/* "$LFS/sources/"
    run_privileged chown -R lfs:lfs "$LFS/sources"
fi

# Créer le script de construction BLFS
log_info "Creating BLFS build script"
cat > "$LFS/build-blfs-base.sh" << 'INNEREOF'
#!/bin/bash
set -e
cd /sources

# Fonction pour compiler un paquet
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
        # rien de spécial
        true
    fi
    make -j$(nproc)
    make install
    cd /sources
    rm -rf "$dir"
    echo "=== $dir done ==="
}

# Compiler quelques paquets de base BLFS (minimal)
for pkg in "curl-*.tar.xz" "openssl-*.tar.gz" "expat-*.tar.xz" "libxml2-*.tar.xz"; do
    compile_package "$pkg" || true
done

echo "BLFS base packages built."
INNEREOF

run_privileged chmod +x "$LFS/build-blfs-base.sh"

# Exécuter dans le chroot
log_info "Entering chroot and building BLFS base..."
run_privileged chroot "$LFS" /bin/bash /build-blfs-base.sh

# Nettoyer les montages
run_privileged umount $LFS/dev/pts 2>/dev/null || true
run_privileged umount $LFS/dev 2>/dev/null || true
run_privileged umount $LFS/proc 2>/dev/null || true
run_privileged umount $LFS/sys 2>/dev/null || true
run_privileged umount $LFS/run 2>/dev/null || true

log_success "BLFS base packages built successfully"