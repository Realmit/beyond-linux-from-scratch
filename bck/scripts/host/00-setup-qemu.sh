#!/bin/bash
# Setup QEMU user emulation for cross-compilation

source scripts/common/utils.sh

log_info "Setting up QEMU user emulation"

# Get QEMU user binary from config
QEMU_USER="${QEMU_USER:-qemu-aarch64-static}"
CROSS_ARCH="${ARCH:-aarch64}"

# Install QEMU if not present
if ! command -v "$QEMU_USER" &> /dev/null; then
    log_info "Installing QEMU user emulation for $CROSS_ARCH"

    case "$CROSS_ARCH" in
        aarch64|arm64)
            apt-get install -y qemu-user-static qemu-system-arm 2>/dev/null || \
            yum install -y qemu-system-arm qemu-user 2>/dev/null || \
            pacman -S --noconfirm qemu-user-static 2>/dev/null
            QEMU_BIN="qemu-aarch64-static"
            ;;
        arm|armv7l)
            apt-get install -y qemu-user-static 2>/dev/null
            QEMU_BIN="qemu-arm-static"
            ;;
        riscv64)
            apt-get install -y qemu-user-static 2>/dev/null
            QEMU_BIN="qemu-riscv64-static"
            ;;
        *)
            log_error "Unsupported architecture for QEMU: $CROSS_ARCH"
            exit 1
            ;;
    esac

    # Register binfmt handlers
    if [ -f /proc/sys/fs/binfmt_misc/register ]; then
        echo ":${CROSS_ARCH}:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/${QEMU_BIN}:F" > /proc/sys/fs/binfmt_misc/register 2>/dev/null || true
    fi
fi

# Copy QEMU binary to LFS sysroot
if [ -n "$SYSROOT" ] && [ -d "$SYSROOT" ]; then
    QEMU_PATH=$(which "$QEMU_USER" 2>/dev/null || which qemu-aarch64-static 2>/dev/null)
    if [ -n "$QEMU_PATH" ]; then
        mkdir -p "$SYSROOT/usr/bin"
        cp "$QEMU_PATH" "$SYSROOT/usr/bin/"
        log_info "QEMU binary copied to sysroot"
    fi
fi

log_success "QEMU user emulation configured for $CROSS_ARCH"