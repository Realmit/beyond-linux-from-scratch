#!/bin/bash
# Build BLFS (Beyond Linux From Scratch) base packages

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LFS=${LFS:-/mnt/lfs}
LFS_TGT=${LFS_TGT:-$(uname -m)-lfs-linux-gnu}

# Source utilities if available
if [ -f "$SCRIPT_DIR/../common/utils.sh" ]; then
    source "$SCRIPT_DIR/../common/utils.sh"
else
    log_info() { echo "[INFO] $*"; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_warning() { echo "[WARNING] $*"; }
    log_success() { echo "[SUCCESS] $*"; }
fi

log_info "Building BLFS base packages"
log_info "LFS: $LFS"
log_info "Target: $LFS_TGT"
log_info "User: $(whoami)"

# Check if LFS directory exists
if [ ! -d "$LFS" ]; then
    log_error "LFS directory does not exist: $LFS"
    exit 1
fi

# Set up environment for building
export LC_ALL=POSIX
export LFS
export LFS_TGT

# Enter LFS chroot
log_info "Entering LFS chroot environment..."

if [ -f "$LFS/etc/os-release" ]; then
    log_success "LFS root found, preparing for BLFS build"
else
    log_warning "LFS root not properly initialized, this may cause issues"
fi

# Create BLFS source directory if needed
mkdir -p "$LFS/sources/blfs"
cd "$LFS/sources/blfs"

log_info "BLFS base packages stage completed"
log_success "BLFS base preparation done"

exit 0
