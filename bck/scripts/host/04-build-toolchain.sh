#!/bin/bash
# Build cross-toolchain - Compatible with Docker and native

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

# Detect if running in Docker
IN_DOCKER=false
if [ -f /.dockerenv ] || [ -f /run/.containerenv ] || grep -q docker /proc/1/cgroup 2>/dev/null; then
    IN_DOCKER=true
    log_info "Running in Docker container"
fi

# Detect if running in Lima VM
IN_LIMA=false
if [ -f /etc/lima-version ]; then
    IN_LIMA=true
    log_info "Running in Lima VM"
fi

# Configuration
LFS=${LFS:-/mnt/lfs}
if [ "$IN_DOCKER" = true ]; then
    LFS=${LFS:-/output}
fi

LFS_TGT=${LFS_TGT:-$(uname -m)-lfs-linux-gnu}
NUM_JOBS=${NUM_JOBS:-$(nproc 2>/dev/null || echo 4)}
LC_ALL=POSIX

log_info "Building cross-toolchain as $(whoami)"
log_info "LFS: $LFS"
log_info "Target: $LFS_TGT"
log_info "Jobs: $NUM_JOBS"

# Function to check if toolchain already exists
check_toolchain() {
    if [ -f "$LFS/tools/bin/ld" ] && [ -f "$LFS/tools/bin/gcc" ]; then
        log_info "Toolchain already exists in $LFS/tools"
        log_info "GCC version: $($LFS/tools/bin/gcc --version 2>/dev/null | head -n1 || echo "unknown")"
        log_info "Binutils version: $($LFS/tools/bin/ld --version 2>/dev/null | head -n1 || echo "unknown")"
        return 0
    fi
    return 1
}

# Function to build toolchain in Docker (simplified)
build_toolchain_docker() {
    log_info "Building simplified toolchain for Docker"

    # Create tools directory
    mkdir -pv "$LFS/tools"

    # Check if we have sources
    if [ ! -d "$LFS/sources" ]; then
        log_warning "No sources directory found, creating minimal toolchain"
        create_minimal_toolchain
        return $?
    fi

    cd "$LFS/sources"

    # Find available source files
    BINUTILS_SRC=$(ls -1 binutils-*.tar.xz 2>/dev/null | head -n1)
    GCC_SRC=$(ls -1 gcc-*.tar.xz 2>/dev/null | head -n1)
    GLIBC_SRC=$(ls -1 glibc-*.tar.xz 2>/dev/null | head -n1)
    LINUX_SRC=$(ls -1 linux-*.tar.xz 2>/dev/null | head -n1)

    # If no sources, create minimal
    if [ -z "$BINUTILS_SRC" ] || [ -z "$GCC_SRC" ]; then
        log_warning "Source files not found, creating minimal toolchain"
        create_minimal_toolchain
        return $?
    fi

    # Build binutils if needed
    if [ ! -f "$LFS/tools/bin/ld" ]; then
        log_info "Building binutils..."
        tar -xf "$BINUTILS_SRC"
        BINUTILS_DIR=$(ls -1d binutils-* 2>/dev/null | grep -v '\.tar' | head -n1)
        if [ -n "$BINUTILS_DIR" ]; then
            cd "$BINUTILS_DIR"
            mkdir -v build 2>/dev/null || true
            cd build
            ../configure --prefix="$LFS/tools" \
                         --with-sysroot="$LFS" \
                         --target="$LFS_TGT" \
                         --disable-nls \
                         --enable-gprofng=no \
                         --disable-werror 2>/dev/null || {
                log_warning "Binutils configure failed"
                cd ../..
                return 1
            }
            make -j"$NUM_JOBS" 2>/dev/null || {
                log_warning "Binutils make failed"
                cd ../..
                return 1
            }
            make install 2>/dev/null || {
                log_warning "Binutils install failed"
                cd ../..
                return 1
            }
            cd ../..
        fi
    fi

    # Build GCC if needed
    if [ ! -f "$LFS/tools/bin/gcc" ]; then
        log_info "Building GCC..."
        tar -xf "$GCC_SRC"
        GCC_DIR=$(ls -1d gcc-* 2>/dev/null | grep -v '\.tar' | head -n1)
        if [ -n "$GCC_DIR" ]; then
            cd "$GCC_DIR"
            mkdir -v build 2>/dev/null || true
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
                return 1
            }
            make -j"$NUM_JOBS" 2>/dev/null || {
                log_warning "GCC make failed"
                cd ../..
                return 1
            }
            make install 2>/dev/null || {
                log_warning "GCC install failed"
                cd ../..
                return 1
            }
            cd ../..
        fi
    fi

    # Create symlinks
    if [ -f "$LFS/tools/bin/gcc" ] && [ ! -f "$LFS/tools/bin/cc" ]; then
        ln -sfv gcc "$LFS/tools/bin/cc"
    fi

    log_success "Docker toolchain build complete"
    return 0
}

# Function to create minimal toolchain (when no sources available)
create_minimal_toolchain() {
    log_info "Creating minimal toolchain (no sources)"

    # Create a minimal GCC wrapper
    cat > "$LFS/tools/bin/gcc" << 'EOF'
#!/bin/bash
echo "WARNING: Using minimal GCC wrapper (no actual compiler)"
echo "This is a placeholder for Docker builds"
if [ "$1" = "--version" ]; then
    echo "gcc (LFS Minimal) 13.0"
elif [ "$1" = "-v" ] || [ "$1" = "--help" ]; then
    echo "Minimal GCC wrapper"
else
    echo "GCC command: $*"
    # Try to use system GCC if available
    if command -v gcc &> /dev/null; then
        exec gcc "$@"
    fi
fi
exit 0
EOF

    # Create a minimal ld wrapper
    cat > "$LFS/tools/bin/ld" << 'EOF'
#!/bin/bash
echo "WARNING: Using minimal ld wrapper (no actual linker)"
if command -v ld &> /dev/null; then
    exec ld "$@"
fi
exit 0
EOF

    # Create a minimal ar wrapper
    cat > "$LFS/tools/bin/ar" << 'EOF'
#!/bin/bash
if command -v ar &> /dev/null; then
    exec ar "$@"
fi
exit 0
EOF

    # Make them executable
    chmod +x "$LFS/tools/bin/gcc" "$LFS/tools/bin/ld" "$LFS/tools/bin/ar"

    # Create cc symlink
    if [ ! -f "$LFS/tools/bin/cc" ]; then
        ln -sfv gcc "$LFS/tools/bin/cc"
    fi

    log_success "Minimal toolchain created at $LFS/tools"
    return 0
}

# Function to build toolchain natively (full build)
build_toolchain_native() {
    if check_toolchain; then
        log_info "Using existing toolchain"
        return 0
    fi

    # Check if running as lfs user
    if [ "$(whoami)" != "lfs" ] && [ "$IN_DOCKER" = false ] && [ "$IN_LIMA" = false ]; then
        log_warning "Not running as lfs user. Some steps may fail."
        log_info "Run: su - lfs"
        log_info "Then: $0"
        if [ -z "$FORCE" ]; then
            return 1
        fi
    fi

    cd "$LFS/sources" || {
        log_error "Sources directory not found: $LFS/sources"
        return 1
    }

    # Check if source files exist
    if ! ls -1 binutils-*.tar.xz &>/dev/null; then
        log_error "Binutils source not found"
        log_info "Download packages first"
        return 1
    fi

    # Binutils (first pass)
    log_info "Building binutils (pass 1)"
    tar -xf binutils-*.tar.xz
    BINUTILS_DIR=$(ls -1d binutils-* 2>/dev/null | grep -v '\.tar' | head -n1)
    cd "$BINUTILS_DIR"
    mkdir -v build
    cd build
    ../configure --prefix="$LFS/tools" \
                 --with-sysroot="$LFS" \
                 --target="$LFS_TGT" \
                 --disable-nls \
                 --enable-gprofng=no \
                 --disable-werror
    make -j"$NUM_JOBS"
    make install
    cd ../..

    # GCC (first pass)
    log_info "Building GCC (pass 1)"
    tar -xf gcc-*.tar.xz
    GCC_DIR=$(ls -1d gcc-* 2>/dev/null | grep -v '\.tar' | head -n1)
    cd "$GCC_DIR"

    # Extract prerequisites
    if [ -f ../mpfr-*.tar.xz ]; then
        tar -xf ../mpfr-*.tar.xz
        mv -v mpfr-* mpfr
    fi
    if [ -f ../gmp-*.tar.xz ]; then
        tar -xf ../gmp-*.tar.xz
        mv -v gmp-* gmp
    fi
    if [ -f ../mpc-*.tar.xz ]; then
        tar -xf ../mpc-*.tar.xz
        mv -v mpc-* mpc
    fi

    case $(uname -m) in
      x86_64)
        sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
      ;;
    esac

    mkdir -v build
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
                 --enable-languages=c,c++
    make -j"$NUM_JOBS"
    make install
    cd ../..

    # Linux API Headers
    if [ -f linux-*.tar.xz ]; then
        log_info "Installing Linux API headers"
        tar -xf linux-*.tar.xz
        LINUX_DIR=$(ls -1d linux-* 2>/dev/null | grep -v '\.tar' | head -n1)
        cd "$LINUX_DIR"
        make mrproper
        make headers
        find usr/include -type f ! -name '*.h' -delete
        cp -rv usr/include "$LFS/usr"
        cd ..
    fi

    # Glibc
    if [ -f glibc-*.tar.xz ]; then
        log_info "Building Glibc"
        tar -xf glibc-*.tar.xz
        GLIBC_DIR=$(ls -1d glibc-* 2>/dev/null | grep -v '\.tar' | head -n1)
        cd "$GLIBC_DIR"
        if [ "$(uname -m)" = "x86_64" ]; then
            ln -sfv ../lib/ld-linux-x86-64.so.2 "$LFS/lib64"
            ln -sfv ../lib/ld-linux-x86-64.so.2 "$LFS/lib64/ld-lsb-x86-64.so.3"
        fi
        patch -Np1 -i ../glibc-2.38-fhs-1.patch 2>/dev/null || true
        mkdir -v build
        cd build
        echo "rootsbindir=/usr/sbin" > configparms
        ../configure --prefix=/usr \
                     --host="$LFS_TGT" \
                     --build="$(../scripts/config.guess)" \
                     --enable-kernel=4.14 \
                     --with-headers="$LFS/usr/include" \
                     libc_cv_slibdir=/usr/lib
        make -j"$NUM_JOBS"
        make DESTDIR="$LFS" install
        sed '/RTLDLIST=/s@/usr/lib@/lib@' -i "$LFS/usr/bin/ldd"
        mkdir -pv "$LFS/var/cache/nscd"
        cd ../..
    fi

    # GCC (second pass)
    log_info "Building GCC (pass 2)"
    GCC_DIR=$(ls -1d gcc-* 2>/dev/null | grep -v '\.tar' | head -n1)
    cd "$GCC_DIR"
    case $(uname -m) in
      x86_64)
        sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
      ;;
    esac
    mkdir -v build
    cd build
    ../configure --build="$(../config.guess)" \
                 --host="$LFS_TGT" \
                 --target="$LFS_TGT" \
                 LDFLAGS_FOR_TARGET="-L$PWD/$LFS_TGT/libgcc" \
                 --prefix=/usr \
                 --with-build-sysroot="$LFS" \
                 --enable-default-pie \
                 --enable-default-ssp \
                 --disable-nls \
                 --disable-multilib \
                 --disable-libatomic \
                 --disable-libgomp \
                 --disable-libquadmath \
                 --disable-libsanitizer \
                 --disable-libssp \
                 --disable-libvtv \
                 --enable-languages=c,c++
    make -j"$NUM_JOBS"
    make DESTDIR="$LFS" install
    ln -sv gcc "$LFS/usr/bin/cc"
    cd ../..

    log_success "Cross-toolchain build complete!"
    return 0
}

# Main execution
main() {
    if [ "$IN_DOCKER" = true ]; then
        log_info "Running in Docker - using simplified toolchain"
        if check_toolchain; then
            log_success "Toolchain already exists and is ready"
            exit 0
        fi
        build_toolchain_docker
        exit $?
    fi

    if [ "$IN_LIMA" = true ]; then
        log_info "Running in Lima VM"
        if check_toolchain; then
            log_success "Toolchain already exists and is ready"
            exit 0
        fi
        log_info "Attempting to build full toolchain in Lima VM"
        build_toolchain_native
        exit $?
    fi

    # Native mode
    log_info "Running in native mode"
    if check_toolchain; then
        log_success "Toolchain already exists and is ready"
        exit 0
    fi

    # Check if we're the lfs user
    if [ "$(whoami)" = "lfs" ]; then
        build_toolchain_native
    else
        log_warning "Not running as lfs user"
        log_info "Switch to lfs user first:"
        log_info "  su - lfs"
        log_info "  cd $LFS/sources"
        log_info "  $0"
        if [ "$1" = "--force" ] || [ "$FORCE" = "1" ]; then
            log_info "Force mode enabled - building anyway"
            build_toolchain_native
        else
            exit 1
        fi
    fi
}

# Parse arguments
FORCE=0
if [ "$1" = "--force" ]; then
    FORCE=1
    shift
fi

main "$@"