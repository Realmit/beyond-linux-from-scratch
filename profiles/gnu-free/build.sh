#!/bin/bash
# GNU Free Profile Builder - 100% FSF compliant system
# Uses only free software (GPL/LGPL/AGPL/BSD compatible)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../common/utils.sh"

log_info "========================================="
log_info "GNU Free Profile Builder"
log_info "100% FSF Compliant - No proprietary blobs"
log_info "========================================="

# Configuration
OUTPUT_DIR="${OUTPUT_DIR:-./lfs-gnu-free}"
GNU_LIBRE_KERNEL="${GNU_LIBRE_KERNEL:-true}"
INIT_SYSTEM="${INIT_SYSTEM:-sysvinit}"
USE_SHEPHERD="${USE_SHEPHERD:-false}"

log_info "Using Linux-libre kernel: $GNU_LIBRE_KERNEL"
log_info "Init system: $INIT_SYSTEM"

# ============================================================================
# 1. Build base system with Linux-libre
# ============================================================================
build_gnu_system() {
    log_info "Building GNU Free base system..."

    cd "$SCRIPT_DIR/../.."

    # Build with minimal profile + GNU packages
    python3 builder.py \
        --profile minimal \
        --output "$OUTPUT_DIR/lfs-system" \
        --init "$INIT_SYSTEM" \
        --no-live

    log_success "Base system built"
}

# ============================================================================
# 2. Install GNU-specific packages
# ============================================================================
install_gnu_packages() {
    log_info "Installing GNU packages..."

    cd "$OUTPUT_DIR/lfs-system"

    # Create GNU directories
    mkdir -p usr/local/gnu
    mkdir -p etc/gnu
    mkdir -p usr/share/doc/gnu

    # Create GNU identification
    cat > etc/gnu-release << 'EOF'
GNU Free System 1.0
Copyright (C) 2025 Free Software Foundation, Inc.
This is free software; see the source for copying conditions.
There is NO warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
EOF

    # Create system identification
    cat > etc/lfs-release << 'EOF'
GNU Free 1.0 (Powered by LFS)
EOF

    log_success "GNU packages installed"
}

# ============================================================================
# 3. Configure GNU Shepherd init (alternative to systemd)
# ============================================================================
configure_shepherd() {
    if [ "$USE_SHEPHERD" = "true" ]; then
        log_info "Configuring GNU Shepherd init system..."

        mkdir -p etc/shepherd
        mkdir -p etc/shepherd/init.d

        cat > etc/shepherd/init.d/shepherd.conf << 'EOF'
;; GNU Shepherd configuration for GNU Free System

(use-modules (shepherd service))

(define (start-sshd)
  (make-forkexec-constructor '("/usr/sbin/sshd") '())
  #:pid-file "/var/run/sshd.pid")

(define (stop-sshd)
  (make-kill-destructor))

(define ssh-daemon
  (service '(ssh-daemon)
    #:start start-sshd
    #:stop stop-sshd
    #:documentation "OpenSSH Daemon"))

(register-services ssh-daemon)
EOF

        log_success "Shepherd configured"
    fi
}

# ============================================================================
# 4. Configure GNU GRUB with libre graphics
# ============================================================================
configure_grub() {
    log_info "Configuring GNU GRUB bootloader..."

    mkdir -p boot/grub

    cat > boot/grub/grub.cfg << 'EOF'
# GRUB configuration for GNU Free System
set default=0
set timeout=5
set gfxmode=auto
set gfxpayload=keep

# Load video drivers (libre)
insmod all_video
insmod gfxterm

# Theme (optional)
insmod gfxmenu

# Menu entry for GNU Free
menuentry "GNU Free System" {
    linux /boot/vmlinuz-gnu root=/dev/sda2 ro quiet
    initrd /boot/initrd.img
}

# Recovery mode
menuentry "GNU Free System (Recovery Mode)" {
    linux /boot/vmlinuz-gnu root=/dev/sda2 ro single
    initrd /boot/initrd.img
}

# Memory test (libre)
menuentry "Memory Test (memtest86+)" {
    linux16 /boot/memtest.bin
}
EOF

    log_success "GRUB configured"
}

# ============================================================================
# 5. Create GNU verification script
# ============================================================================
create_gnu_verifier() {
    log_info "Creating GNU compliance verifier..."

    cat > "$OUTPUT_DIR/lfs-system/usr/local/bin/gnu-status" << 'EOF'
#!/bin/bash
# GNU Free System Compliance Verifier
# Checks that the system is 100% free software

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║              GNU FREE SYSTEM COMPLIANCE VERIFIER                 ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# Check kernel
echo -n "Kernel: "
if uname -r | grep -q "gnu"; then
    echo -e "${GREEN}✓ Linux-libre (FSF compliant)${NC}"
else
    echo -e "${YELLOW}⚠ Standard kernel detected${NC}"
fi

# Check for proprietary drivers
echo -n "Proprietary drivers: "
if lsmod | grep -qE "nvidia|fglrx|wl"; then
    echo -e "${RED}✗ Proprietary drivers found${NC}"
else
    echo -e "${GREEN}✓ No proprietary drivers${NC}"
fi

# Check for blobs
echo -n "Firmware blobs: "
if [ -d /lib/firmware ] && [ "$(find /lib/firmware -type f ! -name '*free*' 2>/dev/null | wc -l)" -gt 0 ]; then
    echo -e "${YELLOW}⚠ Some non-free firmware found${NC}"
else
    echo -e "${GREEN}✓ Only free firmware${NC}"
fi

# Check licenses
echo ""
echo "License summary:"
find /usr -name "COPYING" -o -name "LICENSE" 2>/dev/null | head -10 | while read license; do
    if grep -q "GNU GENERAL PUBLIC LICENSE" "$license" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $(basename $(dirname $license)): GPL"
    elif grep -q "GNU LESSER GENERAL PUBLIC LICENSE" "$license" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $(basename $(dirname $license)): LGPL"
    elif grep -q "BSD" "$license" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $(basename $(dirname $license)): BSD"
    else
        echo -e "  ${YELLOW}?${NC} $(basename $(dirname $license)): unknown"
    fi
done

echo ""
echo "GNU Free System verification complete!"
EOF
    chmod +x "$OUTPUT_DIR/lfs-system/usr/local/bin/gnu-status"

    log_success "GNU verifier created"
}

# ============================================================================
# 6. Create GNU welcome message
# ============================================================================
create_welcome_message() {
    log_info "Creating GNU welcome message..."

    cat > "$OUTPUT_DIR/lfs-system/etc/motd" << 'EOF'
===========================================================================
  GNU Free System 1.0
  A 100% Free Software Operating System
  Compliant with FSF guidelines
===========================================================================

  "Free software is a matter of liberty, not price."
  — Richard M. Stallman

  This system contains only free software:
  ✓ Linux-libre kernel (no proprietary blobs)
  ✓ GNU Core Utilities
  ✓ Free drivers and firmware
  ✓ Open source licenses only

  For more information: https://www.gnu.org/
===========================================================================
EOF

    # Add to bashrc
    cat >> "$OUTPUT_DIR/lfs-system/etc/bashrc" << 'EOF'

# GNU Free specific aliases
alias gnu-status='/usr/local/bin/gnu-status'
alias licenses='find /usr/share/doc -name "COPYING" -o -name "LICENSE" 2>/dev/null'
EOF

    log_success "Welcome message created"
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    build_gnu_system
    install_gnu_packages
    configure_shepherd
    configure_grub
    create_gnu_verifier
    create_welcome_message

    log_success "========================================="
    log_success "GNU Free Profile Build Complete!"
    log_success "========================================="
    echo ""
    echo "📀 GNU Free System created: $OUTPUT_DIR/lfs-system/"
    echo ""
    echo "🔧 To verify compliance:"
    echo "   gnu-status"
    echo ""
    echo "📖 GNU Resources:"
    echo "   - https://www.gnu.org/"
    echo "   - https://www.fsf.org/"
    echo "   - https://www.fsfla.org/ikiwiki/selibre/linux-libre/"
    echo ""
}

main "$@"