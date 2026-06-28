#!/bin/bash
# Build basic LFS system - Compatible with Docker and native Linux
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
    log_info "Running in Docker mode - creating minimal LFS structure"
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

# Mode natif – environnement chroot complet
log_info "Native mode - building basic LFS system with chroot"

mkdir -pv $LFS/{dev,proc,sys,run,etc,home,root,boot,usr,var,lib64,bin,sbin,tmp}
mkdir -pv $LFS/usr/{bin,lib,sbin,include,share}
mkdir -pv $LFS/etc/{profile.d,sysconfig,skel,init.d}
mkdir -pv $LFS/var/{cache,lib,local,lock,log,opt,run,spool,tmp}

# Monter les systèmes de fichiers virtuels
run_privileged mount --bind /dev $LFS/dev 2>/dev/null || true
run_privileged mount -t devpts devpts $LFS/dev/pts 2>/dev/null || true
run_privileged mount -t proc proc $LFS/proc 2>/dev/null || true
run_privileged mount -t sysfs sysfs $LFS/sys 2>/dev/null || true
run_privileged mount -t tmpfs tmpfs $LFS/run 2>/dev/null || true

# Copier les binaires essentiels et leurs dépendances
log_info "Copying essential binaries and libraries..."

binaries=("bash" "sh" "ls" "cp" "mv" "mkdir" "rm" "cat" "echo" "chmod" "chown" "ln" "sed" "grep" "find" "tar" "gzip")

for tool in "${binaries[@]}"; do
    src_path=$(which "$tool" 2>/dev/null || echo "/bin/$tool")
    if [ -f "$src_path" ]; then
        cp -L -v "$src_path" "$LFS/bin/" 2>/dev/null || true
        ldd "$src_path" 2>/dev/null | grep "=> /" | awk '{print $3}' | while read lib; do
            lib_name=$(basename "$lib")
            dest_dir="$LFS/lib"
            if [[ "$lib" == *"/lib64/"* ]]; then
                dest_dir="$LFS/lib64"
            fi
            mkdir -p "$dest_dir"
            cp -v "$lib" "$dest_dir/" 2>/dev/null || true
        done
    fi
done

# Copier explicitement bash et ses dépendances (assure la présence)
bash_src=$(which bash 2>/dev/null || echo "/bin/bash")
if [ -f "$bash_src" ]; then
    cp -L -v "$bash_src" "$LFS/bin/bash" 2>/dev/null || true
    ldd "$bash_src" 2>/dev/null | grep "=> /" | awk '{print $3}' | while read lib; do
        lib_name=$(basename "$lib")
        dest_dir="$LFS/lib"
        if [[ "$lib" == *"/lib64/"* ]]; then
            dest_dir="$LFS/lib64"
        fi
        mkdir -p "$dest_dir"
        cp -v "$lib" "$dest_dir/" 2>/dev/null || true
    done
fi

# Copier la glibc
if [ -d "/lib/x86_64-linux-gnu" ]; then
    cp -rv /lib/x86_64-linux-gnu/* $LFS/lib/ 2>/dev/null || true
fi
if [ -d "/lib64" ]; then
    cp -rv /lib64/* $LFS/lib64/ 2>/dev/null || true
fi

# Copier les fichiers de configuration
cp -v /etc/passwd "$LFS/etc/" 2>/dev/null || true
cp -v /etc/group "$LFS/etc/" 2>/dev/null || true
cp -v /etc/hosts "$LFS/etc/" 2>/dev/null || true

# Vérifier que /bin/bash existe dans le chroot
if [ ! -f "$LFS/bin/bash" ]; then
    log_error "/bin/bash not found in $LFS/bin"
    exit 1
fi

# Créer le script de construction interne
cat > $LFS/build-basic.sh << 'INNEREOF'
#!/bin/bash
set -e
echo "Building basic system inside chroot..."
cd /sources
echo "Basic system build complete (placeholder)"
INNEREOF

chmod +x $LFS/build-basic.sh

# Exécuter le chroot
log_info "Entering chroot..."
run_privileged chroot "$LFS" /bin/bash /build-basic.sh

# Nettoyer les montages
run_privileged umount $LFS/dev/pts 2>/dev/null || true
run_privileged umount $LFS/dev 2>/dev/null || true
run_privileged umount $LFS/proc 2>/dev/null || true
run_privileged umount $LFS/sys 2>/dev/null || true
run_privileged umount $LFS/run 2>/dev/null || true

log_success "Basic LFS system build complete!"