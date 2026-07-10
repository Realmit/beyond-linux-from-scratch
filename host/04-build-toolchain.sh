#!/bin/bash
# Build cross-toolchain - Compatible with Docker and native
# Author : Jean-Francois Landreville, landrevillejf@protonmail.com, 2026.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fallback functions if utils.sh doesn't exist
if [ -f "$SCRIPT_DIR/../common/utils.sh" ]; then
    source "$SCRIPT_DIR/../common/utils.sh"
else
    log_info() { echo "[INFO] $*"; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_warning() { echo "[WARNING] $*"; }
    log_success() { echo "[SUCCESS] $*"; }
fi

# ============================================================================
# INTÉGRATION DU TYPE DE NOYAU (KERNEL_TYPE)
# ============================================================================
# Récupère la variable d'environnement ou utilise la valeur par défaut
# Cette variable sera exportée pour les scripts ultérieurs
KERNEL_TYPE="${KERNEL_TYPE:-linux}"
export KERNEL_TYPE

log_info "Kernel type: $KERNEL_TYPE"

# ============================================================================

# Detect if running in Docker
IN_DOCKER=false
if [ -f /.dockerenv ] || [ -f /run/.containerenv ] || grep -q docker /proc/1/cgroup 2>/dev/null; then
    IN_DOCKER=true
    log_info "Running in Docker container"
fi

# Configuration
if [ "$IN_DOCKER" = true ]; then
    LFS=${LFS:-/output/image}
else
    LFS=${LFS:-/mnt/lfs}
fi

LFS_TGT=${LFS_TGT:-$(uname -m)-lfs-linux-gnu}
NUM_JOBS=${NUM_JOBS:-$(nproc 2>/dev/null || echo 4)}
LC_ALL=POSIX

log_info "Building cross-toolchain as $(whoami)"
log_info "LFS: $LFS"
log_info "Target: $LFS_TGT"
log_info "Jobs: $NUM_JOBS"

# Ensure directories exist
mkdir -pv "$LFS"/{tools,sources}

# Check if toolchain already exists
check_toolchain() {
    # Skip checking toolchain cache in Docker to ensure it builds correctly
    if [ "$IN_DOCKER" = true ]; then
        return 1
    fi
    if [ -f "$LFS/tools/bin/ld" ] && [ -f "$LFS/tools/bin/gcc" ]; then
        log_success "Toolchain already exists at $LFS/tools"
        return 0
    fi
    return 1
}

# Create minimal toolchain for Docker
create_minimal_toolchain() {
    log_info "Creating minimal toolchain for Docker"

    mkdir -pv "$LFS/tools/bin"

    # Use system GCC if available
    if command -v gcc &> /dev/null; then
        log_info "Using system GCC: $(gcc --version | head -n1)"
        # Create symlinks to system tools
        for tool in gcc g++ ld ar ranlib nm strip; do
            if command -v $tool &> /dev/null; then
                ln -sfv $(which $tool) "$LFS/tools/bin/$tool"
            fi
        done
    else
        log_warning "No system compiler found, creating wrappers"
        # Create wrapper scripts
        cat > "$LFS/tools/bin/gcc" << 'WRAPPER'
#!/bin/bash
echo "WARNING: Using minimal GCC wrapper"
if [ "$1" = "--version" ]; then
    echo "gcc (LFS Minimal) 13.0"
else
    echo "GCC: $*"
    # Try to use system GCC if available
    if command -v gcc &> /dev/null; then
        exec gcc "$@"
    fi
fi
exit 0
WRAPPER
        chmod +x "$LFS/tools/bin/gcc"
        ln -sfv gcc "$LFS/tools/bin/cc"
        ln -sfv gcc "$LFS/tools/bin/g++"
    fi

    # Create ld wrapper if needed
    if [ ! -f "$LFS/tools/bin/ld" ]; then
        cat > "$LFS/tools/bin/ld" << 'WRAPPER'
#!/bin/bash
if command -v ld &> /dev/null; then
    exec ld "$@"
else
    echo "WARNING: No ld available"
    exit 0
fi
WRAPPER
        chmod +x "$LFS/tools/bin/ld"
    fi

    log_success "Minimal toolchain created at $LFS/tools"
    return 0
}

# Build toolchain from sources
build_toolchain() {
    log_info "Building toolchain from sources"

    cd "$LFS/sources" || {
        log_error "Sources directory not found: $LFS/sources"
        log_info "Creating minimal toolchain instead"
        create_minimal_toolchain
        return $?
    }

    # Check if we have source files
    if ! ls -1 binutils-*.tar.* &>/dev/null; then
        log_warning "No source files found in $LFS/sources"
        log_info "Creating minimal toolchain instead"
        create_minimal_toolchain
        return $?
    fi

    # Build binutils
    log_info "Building binutils"
    BINUTILS_TAR=$(ls -1 binutils-*.tar.xz 2>/dev/null | head -n1)
    if [ -n "$BINUTILS_TAR" ]; then
        tar -xf "$BINUTILS_TAR"
        BINUTILS_DIR=$(tar -tf "$BINUTILS_TAR" | head -1 | cut -d/ -f1)
        if [ -n "$BINUTILS_DIR" ]; then
            cd "$BINUTILS_DIR"
            mkdir -pv build
            cd build
            ../configure --prefix="$LFS/tools" \
                         --with-sysroot="$LFS" \
                         --target="$LFS_TGT" \
                         --disable-nls \
                         --enable-gprofng=no \
                         --disable-werror 2>/dev/null || {
                log_warning "Binutils configure failed"
                cd ../..
                create_minimal_toolchain
                return $?
            }
            make -j"$NUM_JOBS" 2>/dev/null || {
                log_warning "Binutils make failed"
                cd ../..
                create_minimal_toolchain
                return $?
            }
            make install 2>/dev/null || {
                log_warning "Binutils install failed"
                cd ../..
                create_minimal_toolchain
                return $?
            }
            cd ../..
        fi
    fi

    # Build GCC
    log_info "Building GCC"
    GCC_TAR=$(ls -1 gcc-*.tar.* 2>/dev/null | head -n1)
    if [ -n "$GCC_TAR" ]; then
        tar -xf "$GCC_TAR"
        GCC_DIR=$(tar -tf "$GCC_TAR" | head -1 | cut -d/ -f1)
        if [ -n "$GCC_DIR" ]; then
            cd "$GCC_DIR"
            mkdir -pv build
            cd build
            ../configure --target="$LFS_TGT" \
                         --prefix="$LFS/tools" \
                         --with-glibc-version=2.38 \
                         --with-sysroot="$LFS" \
                         --with-newlib \
                         --without-headers \
                         --enable-default-pie \
                         --enable-default-ssp \
                         --disable-nls \
                         --disable-shared \
                         --disable-multilib \
                         --disable-threads \
                         --disable-libatomic \
                         --disable-libgomp \
                         --disable-libquadmath \
                         --disable-libssp \
                         --disable-libvtv \
                         --disable-libstdcxx \
                         --enable-languages=c,c++ 2>/dev/null || {
                log_warning "GCC configure failed"
                cd ../..
                create_minimal_toolchain
                return $?
            }
            make -j"$NUM_JOBS" 2>/dev/null || {
                log_warning "GCC make failed"
                cd ../..
                create_minimal_toolchain
                return $?
            }
            make install 2>/dev/null || {
                log_warning "GCC install failed"
                cd ../..
                create_minimal_toolchain
                return $?
            }
            cd ../..
        fi
    fi

    # Create cc symlink
    if [ -f "$LFS/tools/bin/gcc" ] && [ ! -f "$LFS/tools/bin/cc" ]; then
        ln -sfv gcc "$LFS/tools/bin/cc"
    fi

    log_success "Toolchain build complete"
    return 0
}

# Main execution
main() {
    if [ "$IN_DOCKER" = true ]; then
        log_info "Running in Docker"

        if check_toolchain; then
            log_success "Toolchain already exists, skipping"
            exit 0
        fi

        log_info "Building toolchain for Docker"
        build_toolchain || create_minimal_toolchain

        log_success "Toolchain setup complete"
        exit 0
    fi

    # Native mode
    if check_toolchain; then
        log_success "Toolchain already exists, skipping"
        exit 0
    fi

    # Check if running as lfs user
    if [ "$(whoami)" != "lfs" ]; then
        log_warning "Not running as lfs user. Switch to lfs user first:"
        log_info "  su - lfs"
        log_info "  cd $LFS/sources"
        log_info "  $0"
        if [ "$1" = "--force" ]; then
            log_info "Force mode enabled - building anyway"
            build_toolchain
        else
            exit 1
        fi
    else
        build_toolchain
    fi

    log_success "Cross-toolchain build complete!"
}

main "$@"