#!/bin/bash
# Build LFS system – VRAIE COMPILATION (glibc, binutils, gcc, etc.)
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
log_info "Building LFS System (REAL COMPILATION)"
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

# ----------------------------------------------------------------------
# 1. S'assurer que /bin/bash existe dans le chroot
# ----------------------------------------------------------------------
if [ ! -f "$LFS/bin/bash" ]; then
    log_warning "/bin/bash not found in $LFS/bin – copying it now"
    BASH_SRC="/bin/bash"
    [ ! -f "$BASH_SRC" ] && BASH_SRC="/usr/bin/bash"
    if [ -f "$BASH_SRC" ]; then
        run_privileged cp -L -v "$BASH_SRC" "$LFS/bin/bash"
        run_privileged chmod +x "$LFS/bin/bash"
        ldd "$BASH_SRC" 2>/dev/null | grep "=> /" | awk '{print $3}' | while read lib; do
            dest_dir="$LFS/lib"
            [[ "$lib" == *"/lib64/"* ]] && dest_dir="$LFS/lib64"
            run_privileged mkdir -p "$dest_dir"
            run_privileged cp -v "$lib" "$dest_dir/"
        done
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

# ----------------------------------------------------------------------
# 2. Tester le chroot
# ----------------------------------------------------------------------
log_info "Testing chroot with /bin/bash"
if ! run_privileged chroot "$LFS" /bin/bash -c "exit 0" 2>/dev/null; then
    log_error "chroot test failed – /bin/bash cannot be executed"
    exit 1
fi
log_success "chroot test passed"

# ----------------------------------------------------------------------
# 3. Monter les systèmes de fichiers virtuels
# ----------------------------------------------------------------------
log_info "Mounting virtual filesystems"
run_privileged mount --bind /dev $LFS/dev 2>/dev/null || true
run_privileged mount -t devpts devpts $LFS/dev/pts 2>/dev/null || true
run_privileged mount -t proc proc $LFS/proc 2>/dev/null || true
run_privileged mount -t sysfs sysfs $LFS/sys 2>/dev/null || true
run_privileged mount -t tmpfs tmpfs $LFS/run 2>/dev/null || true

# ----------------------------------------------------------------------
# 4. Copier les sources dans le chroot
# ----------------------------------------------------------------------
log_info "Copying sources to chroot"
SOURCES_HOST="/tmp/lfs-build/sources"   # là où le builder les a téléchargées
if [ -d "$SOURCES_HOST" ] && [ "$(ls -A $SOURCES_HOST)" ]; then
    run_privileged mkdir -p "$LFS/sources"
    run_privileged cp -rv "$SOURCES_HOST"/* "$LFS/sources/"
    run_privileged chown -R lfs:lfs "$LFS/sources"
    log_success "Sources copied to $LFS/sources"
else
    log_error "No sources found in $SOURCES_HOST"
    exit 1
fi

# ----------------------------------------------------------------------
# 5. Créer le script de construction interne (VRAI BUILD)
# ----------------------------------------------------------------------
log_info "Creating internal build script"
cat > $LFS/build-lfs-system.sh << 'INNEREOF'
#!/bin/bash
set -e
cd /sources

echo "=== Building LFS base system ==="

# Vérifier que les sources sont là
ls -la /sources

# Compiler glibc (exemple)
if [ -f glibc-*.tar.xz ]; then
    echo "Building glibc..."
    tar -xf glibc-*.tar.xz
    cd glibc-*
    mkdir -v build
    cd build
    ../configure --prefix=/usr \
                 --disable-werror \
                 --enable-kernel=3.2 \
                 --enable-stack-protector=strong \
                 --with-headers=/usr/include
    make -j$(nproc)
    make install
    cd /sources
    rm -rf glibc-*
else
    echo "WARNING: glibc source not found"
fi

# Compiler binutils
if [ -f binutils-*.tar.xz ]; then
    echo "Building binutils..."
    tar -xf binutils-*.tar.xz
    cd binutils-*
    mkdir -v build
    cd build
    ../configure --prefix=/usr \
                 --enable-gold \
                 --enable-ld=default \
                 --enable-plugins \
                 --enable-shared \
                 --disable-werror \
                 --enable-64-bit-bfd \
                 --with-system-zlib
    make -j$(nproc)
    make install
    cd /sources
    rm -rf binutils-*
else
    echo "WARNING: binutils source not found"
fi

# Compiler GCC (premier passage)
if [ -f gcc-*.tar.xz ]; then
    echo "Building GCC (pass 1)..."
    tar -xf gcc-*.tar.xz
    cd gcc-*
    mkdir -v build
    cd build
    ../configure --prefix=/usr \
                 --enable-languages=c,c++ \
                 --disable-multilib \
                 --disable-bootstrap \
                 --with-system-zlib
    make -j$(nproc)
    make install
    cd /sources
    rm -rf gcc-*
else
    echo "WARNING: gcc source not found"
fi

echo "=== Base system build complete ==="
INNEREOF

run_privileged chmod +x $LFS/build-lfs-system.sh

# ----------------------------------------------------------------------
# 6. Exécuter le chroot
# ----------------------------------------------------------------------
log_info "Entering chroot and building system..."
run_privileged chroot "$LFS" /bin/bash /build-lfs-system.sh

# ----------------------------------------------------------------------
# 7. Nettoyer les montages
# ----------------------------------------------------------------------
run_privileged umount $LFS/dev/pts 2>/dev/null || true
run_privileged umount $LFS/dev 2>/dev/null || true
run_privileged umount $LFS/proc 2>/dev/null || true
run_privileged umount $LFS/sys 2>/dev/null || true
run_privileged umount $LFS/run 2>/dev/null || true

log_success "LFS system build complete (real compilation)!"