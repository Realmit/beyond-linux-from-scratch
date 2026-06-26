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

# Set LFS directory
if [ "$IN_DOCKER" = true ]; then
    LFS=${LFS:-/output/image}
    SOURCES_DIR="/lfs-builder/packages"
else
    LFS=${LFS:-/mnt/lfs}
    SOURCES_DIR="$LFS/sources"
fi

if [ -z "$LFS" ]; then
    log_error "LFS variable not set"
    exit 1
fi

log_info "Building basic LFS system at $LFS"
log_info "Sources directory: $SOURCES_DIR"

# Function to create directory structure
create_directories() {
    log_info "Creating directory structure"
    
    # Base directories
    for dir in dev proc sys run etc home root boot usr var lib64 bin sbin tmp; do
        mkdir -pv "$LFS/$dir" 2>/dev/null || true
    done
    
    # Usr subdirectories
    for dir in bin lib sbin include share src local; do
        mkdir -pv "$LFS/usr/$dir" 2>/dev/null || true
    done
    
    # Var subdirectories
    for dir in cache lib local lock log opt run spool tmp; do
        mkdir -pv "$LFS/var/$dir" 2>/dev/null || true
    done
    
    # Etc subdirectories
    for dir in profile.d sysconfig skel; do
        mkdir -pv "$LFS/etc/$dir" 2>/dev/null || true
    done
    
    # Set permissions
    chmod -v 1777 "$LFS/tmp" 2>/dev/null || true
    chmod -v 1777 "$LFS/var/tmp" 2>/dev/null || true
    
    # Create sources directory in LFS if it doesn't exist
    if [ ! -d "$LFS/sources" ]; then
        mkdir -pv "$LFS/sources"
        chmod -v a+wt "$LFS/sources" 2>/dev/null || true
    fi
    
    # Copy sources to LFS if running in Docker
    if [ "$IN_DOCKER" = true ] && [ -d "$SOURCES_DIR" ]; then
        log_info "Copying sources to LFS environment..."
        cp -rv "$SOURCES_DIR"/* "$LFS/sources/" 2>/dev/null || true
    fi
}

# Function to copy essential binaries and libraries
copy_essentials() {
    log_info "Copying essential binaries and libraries"
    
    # Create bin directories
    mkdir -p "$LFS/bin" "$LFS/usr/bin" "$LFS/sbin"
    
    # Essential tools to copy
    tools="bash sh ls cp mv mkdir rm cat echo grep sed awk cut sort uniq head tail"
    
    for tool in $tools; do
        # Find the tool in various locations
        tool_path=""
        for path in /bin /usr/bin /usr/local/bin /usr/sbin; do
            if [ -f "$path/$tool" ]; then
                tool_path="$path/$tool"
                break
            fi
        done
        
        if [ -n "$tool_path" ]; then
            cp -v "$tool_path" "$LFS/bin/" 2>/dev/null || true
        fi
    done
    
    # Copy dynamic linker
    if [ -f "/lib64/ld-linux-x86-64.so.2" ]; then
        cp -v /lib64/ld-linux-x86-64.so.2 "$LFS/lib64/" 2>/dev/null || true
    fi
    
    # Copy libraries
    log_info "Copying system libraries"
    
    # For Docker, copy everything from /lib
    if [ "$IN_DOCKER" = true ]; then
        cp -rv /lib/* "$LFS/lib/" 2>/dev/null || true
        cp -rv /usr/lib/* "$LFS/lib/" 2>/dev/null || true
    else
        # Copy libc and other essential libraries
        for lib_dir in /lib /lib64 /usr/lib /usr/lib64; do
            if [ -d "$lib_dir" ]; then
                find "$lib_dir" -maxdepth 1 -name "*.so*" -exec cp -v {} "$LFS/lib/" \; 2>/dev/null || true
            fi
        done
    fi
    
    # Create basic /etc files if they don't exist
    if [ ! -f "$LFS/etc/passwd" ]; then
        cat > "$LFS/etc/passwd" << 'PASSWD'
root:x:0:0:root:/root:/bin/bash
nobody:x:65534:65534:nobody:/:/bin/false
PASSWD
    fi
    
    if [ ! -f "$LFS/etc/group" ]; then
        cat > "$LFS/etc/group" << 'GROUP'
root:x:0:
nobody:x:65534:
GROUP
    fi
    
    if [ ! -f "$LFS/etc/hosts" ]; then
        cat > "$LFS/etc/hosts" << 'HOSTS'
127.0.0.1 localhost
::1 localhost
HOSTS
    fi
    
    if [ ! -f "$LFS/etc/fstab" ]; then
        cat > "$LFS/etc/fstab" << 'FSTAB'
# file system mount-point type options dump pass
/dev/sda3 / ext4 defaults 1 1
/dev/sda1 /boot vfat defaults 1 2
/dev/sda2 swap swap pri=1 0 0
FSTAB
    fi
}

# Function to mount virtual filesystems
mount_virtual_fs() {
    log_info "Mounting virtual filesystems"
    
    # Create mount points
    for dir in dev proc sys run dev/pts; do
        if [ ! -d "$LFS/$dir" ]; then
            mkdir -pv "$LFS/$dir"
        fi
    done
    
    # Mount /dev
    if ! mountpoint -q "$LFS/dev" 2>/dev/null; then
        mount --bind /dev "$LFS/dev" 2>/dev/null || true
    fi
    
    # Mount /dev/pts
    if ! mountpoint -q "$LFS/dev/pts" 2>/dev/null; then
        mount -t devpts devpts "$LFS/dev/pts" 2>/dev/null || true
    fi
    
    # Mount /proc
    if ! mountpoint -q "$LFS/proc" 2>/dev/null; then
        mount -t proc proc "$LFS/proc" 2>/dev/null || true
    fi
    
    # Mount /sys
    if ! mountpoint -q "$LFS/sys" 2>/dev/null; then
        mount -t sysfs sysfs "$LFS/sys" 2>/dev/null || true
    fi
    
    # Mount /run
    if ! mountpoint -q "$LFS/run" 2>/dev/null; then
        mount -t tmpfs tmpfs "$LFS/run" 2>/dev/null || true
    fi
}

# Function to unmount virtual filesystems
umount_virtual_fs() {
    log_info "Unmounting virtual filesystems"
    
    for mount_point in "$LFS/dev/pts" "$LFS/dev" "$LFS/proc" "$LFS/sys" "$LFS/run"; do
        if mountpoint -q "$mount_point" 2>/dev/null; then
            umount "$mount_point" 2>/dev/null || true
        fi
    done
}

# Function to create chroot build script
create_chroot_script() {
    log_info "Creating chroot build script"
    
    cat > "$LFS/build-basic.sh" << 'INNEREOF'
#!/bin/bash
set -e

echo "========================================"
echo "LFS Basic System Build (inside chroot)"
echo "========================================"
echo "Started: $(date)"
echo ""

# Source directory
SOURCES_DIR="/sources"
echo "Sources directory: $SOURCES_DIR"

# Create sources directory if it doesn't exist
if [ ! -d "$SOURCES_DIR" ]; then
    echo "Creating sources directory..."
    mkdir -p "$SOURCES_DIR"
    chmod 1777 "$SOURCES_DIR"
fi

# Check if we have sources
if [ -z "$(ls -A $SOURCES_DIR 2>/dev/null)" ]; then
    echo "WARNING: No sources found in $SOURCES_DIR"
    echo "Creating minimal system..."
    
    # Create minimal system structure
    mkdir -p /usr/bin /usr/lib /etc /var/log /var/run
    
    # Create basic dev files
    if [ ! -e /dev/null ]; then
        mknod -m 0666 /dev/null c 1 3 2>/dev/null || true
    fi
    if [ ! -e /dev/zero ]; then
        mknod -m 0666 /dev/zero c 1 5 2>/dev/null || true
    fi
    
    # Create basic init script
    cat > /etc/inittab << 'INITTAB'
id:3:initdefault:
INITTAB
    
    echo "Minimal system created"
    echo "========================================"
    echo "Basic system setup complete!"
    echo "Completed: $(date)"
    echo "========================================"
    exit 0
fi

# Build packages if sources exist
cd "$SOURCES_DIR" || exit 1

# Function to build a package
build_package() {
    local package=$1
    local config_args=$2
    
    echo "Building $package..."
    
    # Find the source tarball
    local tarball=$(ls ${package}-*.tar.* 2>/dev/null | head -n1)
    if [ -z "$tarball" ]; then
        echo "WARNING: Source for $package not found"
        return 1
    fi
    
    echo "Extracting $tarball..."
    tar -xf "$tarball"
    
    # Get the directory name
    local dir_name=$(echo "$tarball" | sed 's/\.tar\..*$//')
    if [ ! -d "$dir_name" ]; then
        dir_name=$(ls -1d ${package}-* 2>/dev/null | grep -v '\.tar' | head -n1)
    fi
    
    if [ -z "$dir_name" ] || [ ! -d "$dir_name" ]; then
        echo "ERROR: Could not find extracted directory for $package"
        return 1
    fi
    
    cd "$dir_name"
    
    # Build based on package type
    if [ -f "configure" ]; then
        echo "Configuring $package..."
        ./configure $config_args --prefix=/usr
        echo "Making $package..."
        make -j$(nproc)
        echo "Installing $package..."
        make install
    elif [ -f "Makefile" ] || [ -f "makefile" ]; then
        echo "Making $package..."
        make -j$(nproc)
        echo "Installing $package..."
        make install
    elif [ -f "setup.py" ]; then
        echo "Installing Python package..."
        python3 setup.py install
    else
        echo "Unknown build system for $package"
    fi
    
    cd "$SOURCES_DIR"
    rm -rf "$dir_name"
}

# Build essential packages if sources exist
if ls gettext-*.tar.xz 1>/dev/null 2>&1; then
    build_package "gettext" "--disable-shared"
fi

if ls m4-*.tar.xz 1>/dev/null 2>&1; then
    build_package "m4"
fi

if ls bison-*.tar.xz 1>/dev/null 2>&1; then
    build_package "bison"
fi

if ls flex-*.tar.gz 1>/dev/null 2>&1; then
    build_package "flex"
fi

# Setup basic environment
echo "Setting up basic environment..."
cat > /etc/profile << 'PROFILE'
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export PATH=/usr/local/bin:/usr/bin:/bin
export PS1='\u@\h \w\$ '
PROFILE

# Create basic directories
mkdir -p /usr/share/man /usr/share/info

# Create basic init scripts
if [ ! -f /etc/init.d/rcS ]; then
    mkdir -p /etc/init.d
    cat > /etc/init.d/rcS << 'RCS'
#!/bin/sh
echo "Starting system..."
mount -o remount,rw /
mount -a
echo "System started."
RCS
    chmod +x /etc/init.d/rcS
fi

echo ""
echo "========================================"
echo "Basic system build complete!"
echo "Completed: $(date)"
echo "========================================"
INNEREOF

    chmod +x "$LFS/build-basic.sh"
}

# Function to run chroot build
run_chroot_build() {
    log_info "Entering chroot to build basic system"
    
    # Check if bash exists in LFS
    if [ ! -x "$LFS/bin/bash" ] && [ ! -x "$LFS/usr/bin/bash" ]; then
        log_warning "bash not found in LFS environment"
        log_info "Copying bash to LFS..."
        mkdir -p "$LFS/bin"
        if [ -f "/bin/bash" ]; then
            cp -v /bin/bash "$LFS/bin/"
        elif [ -f "/usr/bin/bash" ]; then
            cp -v /usr/bin/bash "$LFS/usr/bin/"
        else
            log_error "bash not found in system"
            return 1
        fi
    fi
    
    # Create build script in LFS
    create_chroot_script
    
    # Run the build script
    if [ "$IN_DOCKER" = true ] || [ "$IN_LIMA" = true ]; then
        log_info "Running in Docker/Lima - executing build script directly"
        # Copy the script to LFS and run it
        if [ -f "$LFS/build-basic.sh" ]; then
            # Try chroot first
            if command -v chroot &> /dev/null; then
                log_info "Attempting chroot build..."
                chroot "$LFS" /bin/bash /build-basic.sh 2>/dev/null || {
                    log_warning "Chroot failed, running script directly in LFS environment"
                    cd "$LFS" && ./build-basic.sh
                }
            else
                log_info "chroot not available, running script directly"
                cd "$LFS" && ./build-basic.sh
            fi
        else
            log_error "Build script not found"
            return 1
        fi
    else
        # Native mode - use chroot
        if command -v chroot &> /dev/null; then
            log_info "Running chroot build..."
            chroot "$LFS" /bin/bash /build-basic.sh
        else
            log_error "chroot command not found"
            return 1
        fi
    fi
    
    return $?
}

# Main execution
main() {
    create_directories
    copy_essentials
    mount_virtual_fs
    create_chroot_script
    
    # Run build if we're in Docker or if explicitly requested
    if [ "$1" = "--build" ] || [ "$IN_DOCKER" = true ] || [ "$IN_LIMA" = true ]; then
        if [ -f "$LFS/build-basic.sh" ]; then
            run_chroot_build
        else
            log_warning "Build script not found, skipping build"
        fi
    fi
    
    # Unmount virtual filesystems (unless in Docker)
    if [ "$IN_DOCKER" = false ] && [ "$IN_LIMA" = false ]; then
        umount_virtual_fs
    else
        log_info "Skipping unmount in Docker/Lima environment"
    fi
    
    log_success "Basic LFS system setup complete!"
    
    if [ "$IN_DOCKER" = true ]; then
        log_info "LFS system is at: $LFS"
        log_info "To enter the chroot environment:"
        log_info "  docker run --rm -it -v \$(pwd)/lfs-output:/output --privileged lfs-builder-mac:latest chroot /output/image /bin/bash"
    else
        log_info "To enter chroot environment:"
        log_info "  chroot $LFS /bin/bash"
    fi
}

# Parse arguments
FORCE_BUILD=0
if [ "$1" = "--build" ]; then
    FORCE_BUILD=1
    shift
fi

main "$@"