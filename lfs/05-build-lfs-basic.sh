#!/bin/bash
# Build basic LFS system – COPIE COMPLÈTE DES BIBLIOTHÈQUES AVEC NETTOYAGE DES LIENS
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

# Native mode
log_info "Native mode - building basic LFS system with chroot"

mkdir -pv $LFS/{dev,proc,sys,run,etc,home,root,boot,usr,var,lib64,bin,sbin,tmp}
mkdir -pv $LFS/usr/{bin,lib,sbin,include,share}
mkdir -pv $LFS/etc/{profile.d,sysconfig,skel,init.d}
mkdir -pv $LFS/var/{cache,lib,local,lock,log,opt,run,spool,tmp}

# ============================================================
# 1. COPIE DE /bin/bash AVEC NETTOYAGE DES LIENS
# ============================================================
log_info "Copying /bin/bash and all host libraries"

# Copier bash (suivre les liens)
BASH_SRC="/bin/bash"
if [ ! -f "$BASH_SRC" ]; then
    BASH_SRC="/usr/bin/bash"
fi
if [ ! -f "$BASH_SRC" ]; then
    log_error "bash not found on host"
    exit 1
fi

# Supprimer tout ancien fichier ou lien
rm -f "$LFS/bin/bash"
cp -L -v "$BASH_SRC" "$LFS/bin/bash"
chmod +x "$LFS/bin/bash"

# ============================================================
# 2. COPIE DE TOUTES LES BIBLIOTHÈQUES (AVEC NETTOYAGE)
# ============================================================
log_info "Copying entire /lib/x86_64-linux-gnu and /lib64"

# Nettoyer les destinations pour éviter les liens pendants
rm -rf "$LFS/lib" "$LFS/lib64" 2>/dev/null || true
mkdir -p "$LFS/lib" "$LFS/lib64"

# Copier les bibliothèques (suivre les liens pour les fichiers individuels)
cp -rvL /lib/x86_64-linux-gnu/* "$LFS/lib/" 2>/dev/null || true
cp -rvL /lib64/* "$LFS/lib64/" 2>/dev/null || true

# ============================================================
# 3. COPIE DE L'INTERPRÉTEUR DYNAMIQUE (ld-linux)
# ============================================================
log_info "Copying ld-linux interpreter"
if [ -f "/lib64/ld-linux-x86-64.so.2" ]; then
    # Supprimer tout lien existant, puis copier le vrai fichier
    rm -f "$LFS/lib64/ld-linux-x86-64.so.2"
    cp -L -v /lib64/ld-linux-x86-64.so.2 "$LFS/lib64/"
elif [ -f "/lib/ld-linux-x86-64.so.2" ]; then
    rm -f "$LFS/lib/ld-linux-x86-64.so.2"
    cp -L -v /lib/ld-linux-x86-64.so.2 "$LFS/lib/"
fi

# ============================================================
# 4. VÉRIFICATION OBLIGATOIRE
# ============================================================
if [ ! -f "$LFS/bin/bash" ]; then
    log_error "/bin/bash not found in $LFS/bin"
    exit 1
fi
if [ ! -f "$LFS/lib64/ld-linux-x86-64.so.2" ] && [ ! -f "$LFS/lib/ld-linux-x86-64.so.2" ]; then
    log_error "ld-linux not found in $LFS (lib64 or lib)"
    exit 1
fi

# ============================================================
# 5. TEST DU CHROOT
# ============================================================
log_info "Testing chroot with /bin/bash"
if ! run_privileged chroot "$LFS" /bin/bash -c "exit 0" 2>/dev/null; then
    log_error "chroot test failed - /bin/bash cannot be executed"
    run_privileged chroot "$LFS" /bin/bash -c "exit 0" || true
    exit 1
fi
log_success "chroot test passed"

# ============================================================
# 6. MONTAGES ET FICHIERS DE CONFIGURATION
# ============================================================
run_privileged mount --bind /dev $LFS/dev 2>/dev/null || true
run_privileged mount -t devpts devpts $LFS/dev/pts 2>/dev/null || true
run_privileged mount -t proc proc $LFS/proc 2>/dev/null || true
run_privileged mount -t sysfs sysfs $LFS/sys 2>/dev/null || true
run_privileged mount -t tmpfs tmpfs $LFS/run 2>/dev/null || true

cp -v /etc/passwd "$LFS/etc/" 2>/dev/null || true
cp -v /etc/group "$LFS/etc/" 2>/dev/null || true
cp -v /etc/hosts "$LFS/etc/" 2>/dev/null || true

# ============================================================
# 7. SCRIPT INTERNE ET CHROOT
# ============================================================
cat > $LFS/build-basic.sh << 'INNEREOF'
#!/bin/bash
set -e
echo "Building basic system inside chroot..."
cd /sources
echo "Basic system build complete (placeholder)"
INNEREOF
chmod +x $LFS/build-basic.sh

log_info "Entering chroot..."
run_privileged chroot "$LFS" /bin/bash /build-basic.sh

# Nettoyage des montages
run_privileged umount $LFS/dev/pts 2>/dev/null || true
run_privileged umount $LFS/dev 2>/dev/null || true
run_privileged umount $LFS/proc 2>/dev/null || true
run_privileged umount $LFS/sys 2>/dev/null || true
run_privileged umount $LFS/run 2>/dev/null || true

log_success "Basic LFS system build complete!"