#!/bin/bash
# final/14-create-installer.sh – Generate a bootable hybrid ISO with installer
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Logger
if [ -f "$SCRIPT_DIR/../common/utils.sh" ]; then
    source "$SCRIPT_DIR/../common/utils.sh"
else
    log_info() { echo "[INFO] $*"; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_warning() { echo "[WARNING] $*"; }
    log_success() { echo "[SUCCESS] $*"; }
fi

# Définir LFS
LFS="${LFS:-/mnt/lfs}"
if [ -z "$LFS" ]; then
    log_error "LFS variable not set"
    exit 1
fi

if [ ! -d "$LFS" ]; then
    log_error "LFS directory '$LFS' does not exist"
    exit 1
fi

# Output ISO location
OUTPUT_DIR="$(dirname "$LFS")"
INSTALLER_ISO="${OUTPUT_DIR}/lfs-installer.iso"
ISO_ROOT="${OUTPUT_DIR}/iso-root"

log_info "========================================="
log_info "Creating bootable installer ISO"
log_info "LFS: $LFS"
log_info "ISO output: $INSTALLER_ISO"
log_info "========================================="

# --- Vérifier les outils requis ---
for tool in xorriso mksquashfs; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        log_error "$tool not found. Please install it."
        exit 1
    fi
done

# --- Vérifier que le noyau et l'initramfs existent ---
KERNEL=$(ls -1 "${LFS}/boot/vmlinuz-"* 2>/dev/null | head -n1)
INITRAMFS=$(ls -1 "${LFS}/boot/initramfs-"* 2>/dev/null | head -n1)
if [ -z "$KERNEL" ] || [ -z "$INITRAMFS" ]; then
    log_error "Kernel or initramfs not found in ${LFS}/boot"
    log_error "Please build the system first"
    exit 1
fi

log_info "Kernel: $KERNEL"
log_info "Initramfs: $INITRAMFS"

# --- Préparer l'arborescence de l'ISO ---
rm -rf "${ISO_ROOT}"
mkdir -p "${ISO_ROOT}"/{boot/grub,isolinux,EFI/BOOT}

# --- 1. Copier le noyau et l'initramfs ---
cp -v "${KERNEL}" "${ISO_ROOT}/boot/vmlinuz"
cp -v "${INITRAMFS}" "${ISO_ROOT}/boot/initramfs.img"

# --- 2. Créer le squashfs du système ---
log_info "Creating squashfs of the built system..."
SQUASHFS_FILE="${ISO_ROOT}/live.squashfs"
mksquashfs "${LFS}" "${SQUASHFS_FILE}" -comp xz -noappend

# --- 3. Config GRUB ---
cat > "${ISO_ROOT}/boot/grub/grub.cfg" << 'EOF'
set timeout=10
set default=0

menuentry "LFS Linux Live" {
    linux /boot/vmlinuz root=/dev/loop0 ro quiet
    initrd /boot/initramfs.img
}

menuentry "Install LFS Linux" {
    linux /boot/vmlinuz root=/dev/loop0 ro quiet install
    initrd /boot/initramfs.img
}

menuentry "Boot from hard disk" {
    chainloader +1
}
EOF

# --- 4. Config isolinux ---
cat > "${ISO_ROOT}/isolinux/isolinux.cfg" << 'EOF'
default live
timeout 10

label live
    kernel /boot/vmlinuz
    append initrd=/boot/initramfs.img root=/dev/loop0 ro quiet

label install
    kernel /boot/vmlinuz
    append initrd=/boot/initramfs.img root=/dev/loop0 ro quiet install

label harddisk
    localboot 0x80
EOF

# --- 5. Script d'installation minimal ---
cat > "${ISO_ROOT}/installer.sh" << 'EOF'
#!/bin/bash
echo "========================================="
echo "  LFS Linux Installer"
echo "========================================="
echo "This is a minimal installer."
echo "For full installation, boot in live mode and run the installer."
EOF
chmod +x "${ISO_ROOT}/installer.sh"

# --- 6. Construire l'ISO ---
log_info "Building ISO image..."
xorriso -as mkisofs \
    -V "LFS_LINUX" \
    -R -J -joliet-long \
    -cache-inodes \
    -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
    -b isolinux/isolinux.bin \
    -c isolinux/boot.cat \
    -boot-load-size 4 -boot-info-table -no-emul-boot \
    -eltorito-alt-boot -e EFI/BOOT/BOOTX64.EFI -no-emul-boot \
    -isohybrid-gpt-basdat \
    -o "${INSTALLER_ISO}" "${ISO_ROOT}"

# Nettoyer
rm -rf "${ISO_ROOT}"

log_success "Installer ISO created at ${INSTALLER_ISO}"
ls -lh "${INSTALLER_ISO}"