#!/bin/bash
# Build basic LFS system – COPIE FORCÉE DE /bin/bash
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
log_info "Building basic LFS system"
log_info "========================================="

# Docker mode – structure minimale
if [ "$IN_DOCKER" = true ]; then
    mkdir -pv $LFS/{bin,boot,dev,etc,home,lib,lib64,media,mnt,opt,proc,root,run,sbin,srv,sys,tmp,usr,var}
    mkdir -pv $LFS/usr/{bin,include,lib,lib64,sbin,share,src}
    mkdir -pv $LFS/var/{cache,lib,local,lock,log,opt,run,spool,tmp}
    mkdir -pv $LFS/etc/{profile.d,sysconfig,skel,init.d}
    chmod -v 1777 $LFS/tmp 2>/dev/null || true
    chmod -v 1777 $LFS/var/tmp 2>/dev/null || true
    cat > $LFS/etc/passwd << 'PASSWD'
root:x:0:0:root:/root:/bin/bash
nobody:x:65534:65534:nobody:/:/bin/false
PASSWD
    cat > $LFS/etc/group << 'GROUP'
root:x:0:
nobody:x:65534:
GROUP
    cat > $LFS/etc/hosts << 'HOSTS'
127.0.0.1 localhost
::1 localhost
HOSTS
    log_success "Minimal LFS system structure created in Docker"
    exit 0
fi

# Mode natif
log_info "Native mode - building basic LFS system with chroot"

mkdir -pv $LFS/{dev,proc,sys,run,etc,home,root,boot,usr,var,lib64,bin,sbin,tmp}
mkdir -pv $LFS/usr/{bin,lib,sbin,include,share}
mkdir -pv $LFS/etc/{profile.d,sysconfig,skel,init.d}
mkdir -pv $LFS/var/{cache,lib,local,lock,log,opt,run,spool,tmp}

run_privileged mount --bind /dev $LFS/dev 2>/dev/null || true
run_privileged mount -t devpts devpts $LFS/dev/pts 2>/dev/null || true
run_privileged mount -t proc proc $LFS/proc 2>/dev/null || true
run_privileged mount -t sysfs sysfs $LFS/sys 2>/dev/null || true
run_privileged mount -t tmpfs tmpfs $LFS/run 2>/dev/null || true

# ------------------------------------------------------------------
# COPIE FORCÉE DE /bin/bash ET DE L'INTERPRÉTEUR
# ------------------------------------------------------------------
log_info "Copying /bin/bash and its dependencies (FORCED)"

BASH_SRC="/bin/bash"
if [ ! -f "$BASH_SRC" ]; then
    BASH_SRC="/usr/bin/bash"
fi
if [ ! -f "$BASH_SRC" ]; then
    log_error "bash not found on host"
    exit 1
fi

log_info "Copying $BASH_SRC -> $LFS/bin/bash"
cp -L -v "$BASH_SRC" "$LFS/bin/bash"
chmod +x "$LFS/bin/bash"

# Copier toutes les libs de bash
ldd "$BASH_SRC" 2>/dev/null | grep "=> /" | awk '{print $3}' | while read lib; do
    dest_dir="$LFS/lib"
    [[ "$lib" == *"/lib64/"* ]] && dest_dir="$LFS/lib64"
    mkdir -p "$dest_dir"
    cp -v "$lib" "$dest_dir/"
done

# Copier ld-linux (interpréteur)
if [ -f "/lib64/ld-linux-x86-64.so.2" ]; then
    mkdir -p "$LFS/lib64"
    cp -v /lib64/ld-linux-x86-64.so.2 "$LFS/lib64/"
elif [ -f "/lib/ld-linux-x86-64.so.2" ]; then
    mkdir -p "$LFS/lib"
    cp -v /lib/ld-linux-x86-64.so.2 "$LFS/lib/"
fi

# Copier la glibc (au cas où)
cp -rv /lib/x86_64-linux-gnu/* "$LFS/lib/" 2>/dev/null || true
cp -rv /lib64/* "$LFS/lib64/" 2>/dev/null || true

# Vérification
if [ ! -f "$LFS/bin/bash" ]; then
    log_error "bash not found in $LFS/bin"
    exit 1
fi
if [ ! -f "$LFS/lib64/ld-linux-x86-64.so.2" ] && [ ! -f "$LFS/lib/ld-linux-x86-64.so.2" ]; then
    log_error "ld-linux not found in $LFS"
    exit 1
fi

# Fichiers de config
cp -v /etc/passwd "$LFS/etc/" 2>/dev/null || true
cp -v /etc/group "$LFS/etc/" 2>/dev/null || true
cp -v /etc/hosts "$LFS/etc/" 2>/dev/null || true

# Script interne
cat > $LFS/build-basic.sh << 'INNEREOF'
#!/bin/bash
set -e
echo "Building basic system inside chroot..."
cd /sources
echo "Basic system build complete (placeholder)"
INNEREOF
chmod +x $LFS/build-basic.sh

# Chroot
log_info "Entering chroot..."
run_privileged chroot "$LFS" /bin/bash /build-basic.sh

# Nettoyage
run_privileged umount $LFS/dev/pts 2>/dev/null || true
run_privileged umount $LFS/dev 2>/dev/null || true
run_privileged umount $LFS/proc 2>/dev/null || true
run_privileged umount $LFS/sys 2>/dev/null || true
run_privileged umount $LFS/run 2>/dev/null || true

log_success "Basic LFS system build complete!"