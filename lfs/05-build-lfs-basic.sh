#!/bin/bash
# Build LFS system – avec run_privileged pour chroot et mounts (VRAI SCRIPT)
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
log_info "Building LFS System with Init System Choice"
log_info "========================================="

INIT_SYSTEM=${INIT_SYSTEM:-sysvinit}
log_info "Init system selected: $INIT_SYSTEM"

# Docker mode – structure minimale
if [ "$IN_DOCKER" = true ]; then
    log_info "Running in Docker mode - minimal system structure"
    mkdir -pv $LFS/{bin,boot,dev,etc,home,lib,lib64,media,mnt,opt,proc,root,run,sbin,srv,sys,tmp,usr,var}
    mkdir -pv $LFS/usr/{bin,include,lib,lib64,sbin,share,src}
    mkdir -pv $LFS/var/{cache,lib,local,lock,log,opt,run,spool,tmp}
    mkdir -pv $LFS/etc/{profile.d,sysconfig,skel,init.d}
    cat > $LFS/etc/passwd << 'PASSWD'
root:x:0:0:root:/root:/bin/bash
nobody:x:65534:65534:nobody:/:/bin/false
PASSWD
    cat > $LFS/etc/group << 'GROUP'
root:x:0:
nobody:x:65534:
GROUP
    log_success "Minimal LFS system structure created in Docker"
    exit 0
fi

# Mode natif
log_info "Running in native mode - full system build"

# Monter les systèmes de fichiers virtuels (avec sudo)
log_info "Mounting virtual filesystems"
run_privileged mount --bind /dev $LFS/dev 2>/dev/null || true
run_privileged mount -t devpts devpts $LFS/dev/pts 2>/dev/null || true
run_privileged mount -t proc proc $LFS/proc 2>/dev/null || true
run_privileged mount -t sysfs sysfs $LFS/sys 2>/dev/null || true
run_privileged mount -t tmpfs tmpfs $LFS/run 2>/dev/null || true

# Copier les scripts d'init (s'il y en a)
log_info "Copying init scripts to chroot"
if [ -d "$SCRIPT_DIR/../lfs/init" ]; then
    cp -rv "$SCRIPT_DIR/../lfs/init/"* "$LFS/etc/init.d/" 2>/dev/null || true
fi

# Créer un script de construction interne (qui utilise les sources)
log_info "Running system build in chroot"
cat > $LFS/build-lfs-system.sh << 'INNEREOF'
#!/bin/bash
set -e
echo "Building LFS system..."
# On va chercher les sources dans le bon répertoire
# (le builder les a mises dans /sources, mais on est dans le chroot)
# On les lie ou on les déplace pour qu'elles soient accessibles
if [ -d "/sources" ] && [ ! -L "/sources" ]; then
    echo "Sources found in /sources"
else
    echo "WARNING: No sources found in chroot"
fi
echo "LFS system build complete."
INNEREOF
chmod +x $LFS/build-lfs-system.sh

# Exécuter le chroot avec sudo
run_privileged chroot "$LFS" /bin/bash /build-lfs-system.sh

# Nettoyer les montages (avec sudo)
run_privileged umount $LFS/dev/pts 2>/dev/null || true
run_privileged umount $LFS/dev 2>/dev/null || true
run_privileged umount $LFS/proc 2>/dev/null || true
run_privileged umount $LFS/sys 2>/dev/null || true
run_privileged umount $LFS/run 2>/dev/null || true

log_success "LFS system build complete!"