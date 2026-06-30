#!/bin/bash
# Install init system – hardcode INIT_SYSTEM in internal script
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
        sudo -E "$@"
    fi
}

log_info "========================================="
log_info "Installing init system"
log_info "========================================="

# Récupérer la valeur depuis l’environnement (ou défaut sysvinit)
INIT_SYSTEM="${INIT_SYSTEM:-sysvinit}"
log_info "Init system selected: $INIT_SYSTEM"

if [ "$IN_DOCKER" = true ]; then
    log_info "Docker mode – creating minimal init structure"
    mkdir -pv "$LFS"/{etc/init.d,bin,sbin,usr/sbin}
    cat > "$LFS/etc/init.d/rcS" << 'EOF'
#!/bin/sh
echo "Starting minimal init..."
exec /bin/bash
EOF
    chmod +x "$LFS/etc/init.d/rcS"
    ln -sf /etc/init.d/rcS "$LFS/sbin/init"
    log_success "Minimal init created for Docker"
    exit 0
fi

if [ ! -f "$LFS/bin/bash" ]; then
    log_error "/bin/bash not found in $LFS/bin – run lfs-basic first"
    exit 1
fi
if ! run_privileged chroot "$LFS" /bin/bash -c "exit 0" 2>/dev/null; then
    log_error "chroot not working – run lfs-basic first"
    exit 1
fi

run_privileged mount --bind /dev $LFS/dev 2>/dev/null || true
run_privileged mount -t devpts devpts $LFS/dev/pts 2>/dev/null || true
run_privileged mount -t proc proc $LFS/proc 2>/dev/null || true
run_privileged mount -t sysfs sysfs $LFS/sys 2>/dev/null || true
run_privileged mount -t tmpfs tmpfs $LFS/run 2>/dev/null || true

# Copy head and cut (needed for compile_package)
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

# Dynamic source path
SOURCES_HOST="$(dirname "$LFS")/sources"
if [ -d "$SOURCES_HOST" ] && [ "$(ls -A "$SOURCES_HOST" 2>/dev/null)" ]; then
    log_info "Copying sources from $SOURCES_HOST to $LFS/sources"
    run_privileged mkdir -p "$LFS/sources"
    run_privileged cp -rv "$SOURCES_HOST"/* "$LFS/sources/"
    run_privileged chown -R lfs:lfs "$LFS/sources"
fi

# --- Créer le script interne avec la valeur hardcodée ---
log_info "Creating internal build script with INIT_SYSTEM=$INIT_SYSTEM"
cat > "$LFS/build-init.sh" << INNEREOF
#!/bin/bash
set -e
cd /sources

# Valeur figée au moment de la génération
INIT_SYSTEM="$INIT_SYSTEM"

compile_package() {
    local pattern=\$1
    local archive=\$(ls -1 \$pattern 2>/dev/null | head -n1)
    if [ -z "\$archive" ]; then
        echo "WARNING: No source found for \$pattern"
        return 1
    fi
    local dir=\$(tar -tf "\$archive" | head -1 | cut -d/ -f1)
    echo "=== Building \$dir ==="
    tar -xf "\$archive"
    cd "\$dir"
    if [ -f "configure" ]; then
        ./configure --prefix=/usr --sysconfdir=/etc
    elif [ -f "Makefile" ]; then
        true
    fi
    make -j\$(nproc)
    make install
    cd /sources
    rm -rf "\$dir"
    echo "=== \$dir done ==="
}

if [ "\$INIT_SYSTEM" = "sysvinit" ]; then
    echo "Building sysvinit..."
    compile_package "sysvinit-*.tar.xz" || compile_package "sysvinit-*.tar.gz"
elif [ "\$INIT_SYSTEM" = "systemd" ]; then
    echo "Building systemd..."
    compile_package "systemd-*.tar.xz" || compile_package "systemd-*.tar.gz"
else
    echo "ERROR: Unknown init system \$INIT_SYSTEM"
    exit 1
fi

echo "Init system installation complete."
INNEREOF

run_privileged chmod +x "$LFS/build-init.sh"

# Exécuter le chroot (plus besoin de passer la variable)
log_info "Entering chroot and building init system..."
run_privileged chroot "$LFS" /bin/bash /build-init.sh

run_privileged umount $LFS/dev/pts 2>/dev/null || true
run_privileged umount $LFS/dev 2>/dev/null || true
run_privileged umount $LFS/proc 2>/dev/null || true
run_privileged umount $LFS/sys 2>/dev/null || true
run_privileged umount $LFS/run 2>/dev/null || true

log_success "Init system ($INIT_SYSTEM) installed successfully"