#!/bin/bash
set -e

# ============================================================================
# Compilation du noyau Linux (ou Linux-libre) selon KERNEL_TYPE
# ============================================================================

LFS=${LFS:-/mnt/lfs}
KERNEL_TYPE=${KERNEL_TYPE:-linux}   # Valeur par défaut

log_info() { echo "[INFO] $*"; }
log_error() { echo "[ERROR] $*" >&2; }
log_success() { echo "[SUCCESS] $*"; }

# Monter les systèmes de fichiers virtuels si ce n'est pas déjà fait (avec sudo)
sudo mountpoint -q "$LFS/dev"  || sudo mount --bind /dev "$LFS/dev"
sudo mountpoint -q "$LFS/dev/pts" || sudo mount -t devpts devpts "$LFS/dev/pts"
sudo mountpoint -q "$LFS/proc" || sudo mount -t proc proc "$LFS/proc"
sudo mountpoint -q "$LFS/sys"  || sudo mount -t sysfs sysfs "$LFS/sys"

# Nettoyage en fin de script (même en cas d'erreur)
cleanup() {
    sudo umount "$LFS/dev/pts" 2>/dev/null || true
    sudo umount "$LFS/dev" 2>/dev/null || true
    sudo umount "$LFS/proc" 2>/dev/null || true
    sudo umount "$LFS/sys" 2>/dev/null || true
}
trap cleanup EXIT

# Vérifier que le répertoire des sources existe
if [ ! -d "$LFS/sources" ]; then
    log_error "Sources directory $LFS/sources not found"
    exit 1
fi

# Trouver l'archive du noyau correspondant au type demandé
cd "$LFS/sources"
KERNEL_ARCHIVE=$(ls -1 "${KERNEL_TYPE}"-*.tar.xz 2>/dev/null | head -n1)
if [ -z "$KERNEL_ARCHIVE" ]; then
    log_error "No kernel source found for type: $KERNEL_TYPE (pattern: ${KERNEL_TYPE}-*.tar.xz)"
    exit 1
fi
log_info "Using kernel source: $KERNEL_ARCHIVE"

# Extraire le nom du répertoire (sans l'extension)
KERNEL_DIR=$(tar -tf "$KERNEL_ARCHIVE" | head -1 | cut -d/ -f1)
log_info "Kernel directory: $KERNEL_DIR"

# Si le noyau est déjà compilé, on peut sauter (optionnel)
if [ -f "$LFS/boot/vmlinuz" ]; then
    log_info "Kernel already installed at $LFS/boot/vmlinuz – skipping compilation"
    exit 0
fi

# Compilation dans un chroot (avec sudo)
sudo chroot "$LFS" /bin/bash << EOF
set -e
cd /sources
tar -xf "$KERNEL_ARCHIVE"
cd "$KERNEL_DIR"
make mrproper
make defconfig
make -j\$(nproc)
make modules_install
cp arch/x86/boot/bzImage /boot/vmlinuz
cp System.map /boot/System.map
cd /sources
rm -rf "$KERNEL_DIR"
EOF

log_success "Kernel $KERNEL_TYPE compiled and installed to $LFS/boot/vmlinuz"