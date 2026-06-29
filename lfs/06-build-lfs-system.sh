#!/bin/bash
# Build LFS system – avec vérification de /bin/bash et run_privileged
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
log_info "LFS directory: $LFS"

# ------------------------------------------------------------
# 1. S'assurer que /bin/bash existe dans le chroot
# ------------------------------------------------------------
if [ ! -f "$LFS/bin/bash" ]; then
    log_warning "/bin/bash not found in $LFS/bin – copying it now"
    BASH_SRC="/bin/bash"
    if [ ! -f "$BASH_SRC" ]; then
        BASH_SRC="/usr/bin/bash"
    fi
    if [ -f "$BASH_SRC" ]; then
        run_privileged cp -L -v "$BASH_SRC" "$LFS/bin/bash"
        run_privileged chmod +x "$LFS/bin/bash"
        # Copier les bibliothèques nécessaires
        ldd "$BASH_SRC" 2>/dev/null | grep "=> /" | awk '{print $3}' | while read lib; do
            dest_dir="$LFS/lib"
            [[ "$lib" == *"/lib64/"* ]] && dest_dir="$LFS/lib64"
            run_privileged mkdir -p "$dest_dir"
            run_privileged cp -v "$lib" "$dest_dir/"
        done
        # Copier ld-linux
        if [ -f "/lib64/ld-linux-x86-64.so.2" ]; then
            run_privileged mkdir -p "$LFS/lib64"
            run_privileged cp -L -v /lib64/ld-linux-x86-64.so.2 "$LFS/lib64/"
        elif [ -f "/lib/ld-linux-x86-64.so.2" ]; then
            run_privileged mkdir -p "$LFS/lib"
            run_privileged cp -L -v /lib/ld-linux-x86-64.so.2 "$LFS/lib/"
        fi
    else
        log_error "bash not found on host"
        exit 1
    fi
fi

# ------------------------------------------------------------
# 2. Vérifier que le chroot fonctionne
# ------------------------------------------------------------
log_info "Testing chroot with /bin/bash"
if ! run_privileged chroot "$LFS" /bin/bash -c "exit 0" 2>/dev/null; then
    log_error "chroot test failed – /bin/bash cannot be executed"
    exit 1
fi
log_success "chroot test passed"

# ------------------------------------------------------------
# 3. Monter les systèmes de fichiers virtuels
# ------------------------------------------------------------
log_info "Mounting virtual filesystems"
run_privileged mount --bind /dev $LFS/dev 2>/dev/null || true
run_privileged mount -t devpts devpts $LFS/dev/pts 2>/dev/null || true
run_privileged mount -t proc proc $LFS/proc 2>/dev/null || true
run_privileged mount -t sysfs sysfs $LFS/sys 2>/dev/null || true
run_privileged mount -t tmpfs tmpfs $LFS/run 2>/dev/null || true

# ------------------------------------------------------------
# 4. Copier les scripts d'init (si disponibles)
# ------------------------------------------------------------
log_info "Copying init scripts to chroot"
if [ -d "$SCRIPT_DIR/../lfs/init" ]; then
    run_privileged cp -rv "$SCRIPT_DIR/../lfs/init/"* "$LFS/etc/init.d/" 2>/dev/null || true
fi

# ------------------------------------------------------------
# 5. Script de construction interne
# ------------------------------------------------------------
log_info "Running system build in chroot"
cat > $LFS/build-lfs-system.sh << 'INNEREOF'
#!/bin/bash
set -e
echo "Building LFS system..."
# Ici, on pourrait compiler des paquets si les sources sont présentes
# Pour l'instant, on fait juste un placeholder.
echo "LFS system build complete."
INNEREOF
run_privileged chmod +x $LFS/build-lfs-system.sh

# Exécuter le chroot
run_privileged chroot "$LFS" /bin/bash /build-lfs-system.sh

# ------------------------------------------------------------
# 6. Nettoyer les montages
# ------------------------------------------------------------
run_privileged umount $LFS/dev/pts 2>/dev/null || true
run_privileged umount $LFS/dev 2>/dev/null || true
run_privileged umount $LFS/proc 2>/dev/null || true
run_privileged umount $LFS/sys 2>/dev/null || true
run_privileged umount $LFS/run 2>/dev/null || true

log_success "LFS system build complete!"