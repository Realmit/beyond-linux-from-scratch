#!/bin/bash
# Build LFS system – VRAIE COMPILATION DE GLIBC, BINUTILS, GCC, ETC.
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
log_info "Building LFS system (REAL COMPILATION)"
log_info "========================================="

INIT_SYSTEM=${INIT_SYSTEM:-sysvinit}
log_info "Init system: $INIT_SYSTEM"

# Docker mode – structure minimale (ne fait rien)
if [ "$IN_DOCKER" = true ]; then
    log_info "Docker mode – skipping compilation"
    exit 0
fi

# Vérifier que le chroot est fonctionnel (bash doit être là)
if [ ! -f "$LFS/bin/bash" ]; then
    log_error "/bin/bash not found in $LFS/bin – run lfs-basic first"
    exit 1
fi
if ! run_privileged chroot "$LFS" /bin/bash -c "exit 0" 2>/dev/null; then
    log_error "chroot not working – run lfs-basic first"
    exit 1
fi

# Monter les FS si pas déjà faits
run_privileged mount --bind /dev $LFS/dev 2>/dev/null || true
run_privileged mount -t devpts devpts $LFS/dev/pts 2>/dev/null || true
run_privileged mount -t proc proc $LFS/proc 2>/dev/null || true
run_privileged mount -t sysfs sysfs $LFS/sys 2>/dev/null || true
run_privileged mount -t tmpfs tmpfs $LFS/run 2>/dev/null || true

# Copier les sources depuis /tmp/lfs-build/sources vers $LFS/sources
SOURCES_HOST="/tmp/lfs-build/sources"
if [ -d "$SOURCES_HOST" ] && [ "$(ls -A $SOURCES_HOST 2>/dev/null)" ]; then
    log_info "Copying sources from $SOURCES_HOST to $LFS/sources"
    run_privileged mkdir -p "$LFS/sources"
    run_privileged cp -rv "$SOURCES_HOST"/* "$LFS/sources/"
    run_privileged chown -R lfs:lfs "$LFS/sources"
else
    log_error "No sources found in $SOURCES_HOST – cannot compile"
    exit 1
fi

# Créer le script de compilation INTERNE (qui sera exécuté dans le chroot)
log_info "Creating internal compilation script"
cat > $LFS/build-lfs-system.sh << 'INNEREOF'
#!/bin/bash
set -e

cd /sources

# Fonction pour compiler un paquet avec gestion d'erreur
compile_package() {
    local archive=$1
    local pkg_name=$(echo $archive | sed -E 's/\.tar\.[a-z0-9]+$//')
    echo "=== Building $pkg_name ==="
    tar -xf $archive
    cd $pkg_name
    # Si le paquet a un sous-dossier build standard, on l'utilise
    if [ -d "build" ]; then
        cd build
    elif [ -d "build-aux" ]; then
        cd build-aux
    fi
    # Ici on appelle les commandes de configuration et compilation.
    # On va détecter automatiquement le type de build (autotools, cmake, etc.)
    if [ -f "configure" ]; then
        ./configure --prefix=/usr --disable-werror
    elif [ -f "CMakeLists.txt" ]; then
        cmake -DCMAKE_INSTALL_PREFIX=/usr .
    else
        # Sinon, on utilise make directement
        true
    fi
    make -j$(nproc)
    make install
    cd /sources
    rm -rf $pkg_name
    echo "=== $pkg_name done ==="
}

# Vérifier les sources et compiler les paquets essentiels
# glibc
if ls glibc-*.tar.xz 1> /dev/null 2>&1; then
    compile_package $(ls glibc-*.tar.xz | head -n1)
else
    echo "WARNING: glibc source not found"
fi

# binutils
if ls binutils-*.tar.xz 1> /dev/null 2>&1; then
    compile_package $(ls binutils-*.tar.xz | head -n1)
else
    echo "WARNING: binutils source not found"
fi

# gcc (premier passage)
if ls gcc-*.tar.xz 1> /dev/null 2>&1; then
    compile_package $(ls gcc-*.tar.xz | head -n1)
else
    echo "WARNING: gcc source not found"
fi

# Compiler quelques utilitaires de base si présents
for pkg in coreutils bash make grep sed gawk findutils tar gzip; do
    if ls $pkg-*.tar.* 1> /dev/null 2>&1; then
        # On prend le premier fichier trouvé
        archive=$(ls $pkg-*.tar.* | head -n1)
        compile_package $archive
    fi
done

echo "=== Base system compilation complete ==="
INNEREOF

run_privileged chmod +x $LFS/build-lfs-system.sh

# Exécuter le chroot
log_info "Entering chroot and compiling..."
run_privileged chroot "$LFS" /bin/bash /build-lfs-system.sh

# Nettoyer les montages
run_privileged umount $LFS/dev/pts 2>/dev/null || true
run_privileged umount $LFS/dev 2>/dev/null || true
run_privileged umount $LFS/proc 2>/dev/null || true
run_privileged umount $LFS/sys 2>/dev/null || true
run_privileged umount $LFS/run 2>/dev/null || true

log_success "LFS system build complete (real compilation done)"