#!/bin/bash
# final/14-create-installer.sh – Generate a bootable hybrid ISO with installer
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

# Output ISO location
OUTPUT_DIR="$(dirname "$LFS")"
INSTALLER_ISO="${OUTPUT_DIR}/lfs-installer.iso"
ISO_ROOT="${OUTPUT_DIR}/iso-root"

run_privileged() {
    if [ "$(whoami)" = "root" ]; then
        "$@"
    else
        sudo "$@"
    fi
}

log_info "========================================="
log_info "Creating bootable installer ISO"
log_info "========================================="

if [ "$IN_DOCKER" = true ]; then
    log_info "Docker mode – creating a minimal ISO placeholder"
    # In Docker we can't run xorriso (usually not installed), so create a dummy.
    # But we can still produce a valid ISO if xorriso is available.
    # We'll try to use xorriso, and if not, create a placeholder.
    if command -v xorriso >/dev/null 2>&1; then
        log_info "xorriso found, creating real ISO"
    else
        log_warning "xorriso not found, creating placeholder ISO"
        echo "This is a placeholder ISO for Docker mode" > "${INSTALLER_ISO}"
        log_success "Placeholder ISO created at ${INSTALLER_ISO}"
        exit 0
    fi
fi

# Ensure we have xorriso
if ! command -v xorriso >/dev/null 2>&1 && ! command -v grub-mkrescue >/dev/null 2>&1; then
    log_error "Neither xorriso nor grub-mkrescue found. Please install xorriso (or grub-common)."
    exit 1
fi

# Prepare ISO root directory
rm -rf "${ISO_ROOT}"
mkdir -p "${ISO_ROOT}"/{boot/grub,isolinux,EFI/BOOT}

# --- 1. Copy kernel and initramfs from the built system ---
KERNEL=$(ls -1 "${LFS}/boot/vmlinuz-"* 2>/dev/null | head -n1)
INITRAMFS=$(ls -1 "${LFS}/boot/initramfs-"* 2>/dev/null | head -n1)
if [ -z "$KERNEL" ] || [ -z "$INITRAMFS" ]; then
    log_warning "Kernel or initramfs not found in ${LFS}/boot. Creating dummy files for ISO."
    KERNEL="${ISO_ROOT}/boot/vmlinuz"
    INITRAMFS="${ISO_ROOT}/boot/initramfs.img"
    # Create dummy kernel and initramfs (just for structure, not bootable)
    touch "${KERNEL}" "${INITRAMFS}"
else
    run_privileged cp -v "${KERNEL}" "${ISO_ROOT}/boot/vmlinuz"
    run_privileged cp -v "${INITRAMFS}" "${ISO_ROOT}/boot/initramfs.img"
fi

# --- 2. Create a minimal root filesystem for the live/install environment ---
# We'll use the entire built system as the root, but we need to compress it into a squashfs.
# For simplicity, we'll just copy the system as is (if space permits), or use squashfs.
# Here we copy the entire system to the ISO root (so it becomes the live root).
# But that may be huge. Better to create a squashfs image.
log_info "Creating squashfs of the built system for live environment"
SQUASHFS_FILE="${ISO_ROOT}/live.squashfs"
if command -v mksquashfs >/dev/null 2>&1; then
    run_privileged mksquashfs "${LFS}" "${SQUASHFS_FILE}" -comp xz -noappend
else
    log_warning "mksquashfs not found; will copy the system directly (ISO will be large)."
    run_privileged cp -a "${LFS}" "${ISO_ROOT}/root"
fi

# --- 3. Create GRUB configuration for the ISO ---
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

# --- 4. Create an isolinux config for BIOS boot (if using isolinux) ---
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

# --- 5. Create a simple installer script to be placed in the initramfs or rootfs ---
# This will be run if the kernel parameter "install" is passed.
# We'll embed it in the rootfs (in /usr/local/bin/installer.sh) – but we already have the system.
# For now, we just create a placeholder installer script in the ISO root.
cat > "${ISO_ROOT}/installer.sh" << 'EOF'
#!/bin/bash
echo "Welcome to LFS Installer"
echo "This is a minimal installer. Please run the full installation from the live system."
EOF
chmod +x "${ISO_ROOT}/installer.sh"

# --- 6. Build the ISO using xorriso or grub-mkrescue ---
log_info "Building ISO image..."
if command -v xorriso >/dev/null 2>&1; then
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
else
    # Fallback to grub-mkrescue
    grub-mkrescue -o "${INSTALLER_ISO}" "${ISO_ROOT}"
fi

# Clean up
rm -rf "${ISO_ROOT}"

log_success "Installer ISO created at ${INSTALLER_ISO}"
ls -lh "${INSTALLER_ISO}"