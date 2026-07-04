#!/bin/bash
# macOS LFS Builder using Docker
# Version: 4.3.0 - Updated for all profiles and cross-compilation

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_success() { echo -e "${BLUE}[SUCCESS]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

# ============================================================================
# CONFIGURATION
# ============================================================================

# Default values
OUTPUT_DIR="${OUTPUT_DIR:-${HOME}/lfs-output}"
DOCKER_IMAGE="lfs-builder-mac:latest"
PROFILE="${PROFILE:-xfce}"
INIT_SYSTEM="${INIT_SYSTEM:-sysvinit}"
CONFIG_FILE="${CONFIG_FILE:-config/build.conf.json}"
BUILD_THREADS="${BUILD_THREADS:-$(sysctl -n hw.ncpu)}"
CROSS_COMPILE="${CROSS_COMPILE:-false}"
TARGET_ARCH="${TARGET_ARCH:-x86_64}"
LIVE_SYSTEM="${LIVE_SYSTEM:-true}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --profile|-p)
            PROFILE="$2"
            shift 2
            ;;
        --init|-i)
            INIT_SYSTEM="$2"
            shift 2
            ;;
        --config|-c)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --output|-o)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --arm64|-a)
            CROSS_COMPILE="true"
            TARGET_ARCH="aarch64"
            PROFILE="arm64"
            shift
            ;;
        --pinebook)
            CROSS_COMPILE="true"
            TARGET_ARCH="aarch64"
            PROFILE="pinebook"
            CONFIG_FILE="config/build-pinebook.conf"
            shift
            ;;
        --brax3)
            CROSS_COMPILE="true"
            TARGET_ARCH="aarch64"
            PROFILE="brax3"
            CONFIG_FILE="config/build-brax3.conf"
            shift
            ;;
        --audio-studio)
            PROFILE="audio-studio"
            shift
            ;;
        --audio-cli)
            PROFILE="audio-cli"
            INIT_SYSTEM="sysvinit"
            shift
            ;;
        --no-live)
            LIVE_SYSTEM="false"
            shift
            ;;
        --help|-h)
            cat << EOF
Usage: $0 [OPTIONS]

Options:
    --profile, -p <name>    Build profile (default: xfce)
                            Available: minimal, xfce, gnome, kde, lxqt,
                                       java-dev, server, secure, full,
                                       arm64, audio-cli, audio-studio,
                                       pinebook, brax3

    --init, -i <system>     Init system (default: sysvinit)
                            Available: sysvinit, systemd, openrc, runit, s6

    --config, -c <file>     Configuration file path

    --output, -o <dir>      Output directory (default: ~/lfs-output)

    --arm64, -a             Build for ARM64 (Raspberry Pi, etc.)

    --pinebook              Build for Pinebook/Pinebook Pro

    --brax3                 Build for Brax3 Linux smartphone

    --audio-studio          Build audio production studio (XFCE + systemd)

    --audio-cli             Build CLI audio production (sysvinit)

    --no-live               Disable live system creation

    --help, -h              Show this help message

Examples:
    $0                                      # Build default XFCE
    $0 --profile minimal --init sysvinit    # Build minimal system
    $0 --arm64                              # Build for ARM64
    $0 --pinebook                           # Build for Pinebook Pro
    $0 --brax3                              # Build for Brax3 smartphone
    $0 --audio-studio                       # Build audio production studio
    $0 --profile full --no-live             # Build full system without live USB
EOF
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# ============================================================================
# DISPLAY CONFIGURATION
# ============================================================================

print_banner() {
    cat << "BANNER"
╔═══════════════════════════════════════════════════════════════════════════╗
║                                                                           ║
║     ██╗     ███████╗███████╗    ██████╗ ██╗   ██╗██╗██╗     ██████╗      ║
║     ██║     ██╔════╝██╔════╝    ██╔══██╗██║   ██║██║██║     ██╔══██╗     ║
║     ██║     █████╗  ███████╗    ██████╔╝██║   ██║██║██║     ██║  ██║     ║
║     ██║     ██╔══╝  ╚════██║    ██╔══██╗██║   ██║██║██║     ██║  ██║     ║
║     ███████╗██║     ███████║    ██████╔╝╚██████╔╝██║███████╗██████╔╝     ║
║     ╚══════╝╚═╝     ╚══════╝    ╚═════╝  ╚═════╝ ╚═╝╚══════╝╚═════╝      ║
║                                                                           ║
║                    macOS LFS Builder v4.3.0                               ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝
BANNER
}

print_config() {
    echo ""
    log_step "Build Configuration:"
    echo "  Profile:        $PROFILE"
    echo "  Init System:    $INIT_SYSTEM"
    echo "  Output Dir:     $OUTPUT_DIR"
    echo "  Architecture:   $([ "$CROSS_COMPILE" = "true" ] && echo "ARM64 (aarch64)" || echo "x86_64")"
    echo "  Live System:    $([ "$LIVE_SYSTEM" = "true" ] && echo "Enabled" || echo "Disabled")"
    echo "  Build Threads:  $BUILD_THREADS"
    echo "  Docker Image:   $DOCKER_IMAGE"
    echo ""
}

# ============================================================================
# CHECK PREREQUISITES
# ============================================================================

check_docker() {
    log_step "Checking Docker..."

    if ! command -v docker &> /dev/null; then
        log_error "Docker not installed"
        echo ""
        echo "Install Docker Desktop from:"
        echo "  https://www.docker.com/products/docker-desktop"
        echo ""
        echo "After installation, restart this script."
        exit 1
    fi

    if ! docker info &> /dev/null; then
        log_error "Docker not running"
        echo ""
        echo "Please start Docker Desktop from Applications"
        echo "Wait for Docker to fully start, then retry."
        exit 1
    fi

    log_success "Docker is ready"
}

check_disk_space() {
    log_step "Checking disk space..."

    available=$(df -g "$OUTPUT_DIR" 2>/dev/null | tail -1 | awk '{print $4}')
    if [ -z "$available" ]; then
        # If OUTPUT_DIR doesn't exist yet, check home directory
        available=$(df -g "$HOME" | tail -1 | awk '{print $4}')
    fi

    required=50  # 50GB required
    if [ "$available" -lt "$required" ]; then
        log_warning "Low disk space: ${available}GB available (${required}GB recommended)"
        echo "  Consider freeing up space or using an external drive"
        echo "  You can change output directory with: --output /Volumes/ExternalDrive/lfs"
    else
        log_success "Disk space OK: ${available}GB available"
    fi
}

# ============================================================================
# DOCKER SETUP
# ============================================================================

create_dockerfile() {
    cat > Dockerfile.mac << 'EOF'
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# Install base packages
RUN apt update && apt install -y \
    build-essential \
    bison \
    flex \
    gawk \
    texinfo \
    wget \
    curl \
    git \
    python3 \
    python3-pip \
    xorriso \
    isolinux \
    mtools \
    dosfstools \
    parted \
    rsync \
    sudo \
    bc \
    cpio \
    kmod \
    libssl-dev \
    libelf-dev \
    file \
    unzip \
    xz-utils \
    zstd \
    squashfs-tools \
    && rm -rf /var/lib/apt/lists/*

# Install cross-compilation toolchain for ARM64
RUN apt update && apt install -y \
    gcc-aarch64-linux-gnu \
    binutils-aarch64-linux-gnu \
    qemu-user-static \
    && rm -rf /var/lib/apt/lists/*

# Install additional tools
RUN pip3 install --no-cache-dir \
    meson \
    ninja \
    jinja2 \
    markupsafe

# Create builder user
RUN useradd -m -G sudo builder && \
    echo "builder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER builder
WORKDIR /home/builder

# Setup environment
RUN echo 'export PATH=$PATH:/home/builder/.local/bin' >> /home/builder/.bashrc

CMD ["/bin/bash"]
EOF
    log_success "Dockerfile created"
}

build_docker_image() {
    log_step "Building Docker image..."

    if docker images --format "table {{.Repository}}:{{.Tag}}" | grep -q "$DOCKER_IMAGE"; then
        log_warning "Docker image already exists. Rebuilding..."
        docker rmi "$DOCKER_IMAGE" 2>/dev/null || true
    fi

    docker build -t "$DOCKER_IMAGE" -f Dockerfile.mac . --progress=plain

    log_success "Docker image built"
}

# ============================================================================
# LFS BUILD
# ============================================================================

prepare_output_directory() {
    log_step "Preparing output directory..."

    mkdir -p "$OUTPUT_DIR"/{sources,logs,image,cache,backups}

    log_success "Output directory ready: $OUTPUT_DIR"
}

run_build() {
    log_step "Starting LFS build in Docker..."
    log_info "This may take several hours depending on your profile"
    echo ""

    # Build the command
    local docker_cmd="
        cd /lfs-builder
        python3 builder.py \
            --profile $PROFILE \
            --output /output \
            --config $CONFIG_FILE \
            --init $INIT_SYSTEM
    "

    # Add options
    if [ "$LIVE_SYSTEM" = "false" ]; then
        docker_cmd="$docker_cmd --no-live"
    fi

    if [ "$CROSS_COMPILE" = "true" ]; then
        docker_cmd="$docker_cmd --config config/build-cross.conf"
        log_info "Cross-compilation for ARM64 enabled"
    fi

    # Run Docker container
    docker run --rm --privileged \
        --cap-add=SYS_ADMIN \
        --security-opt seccomp=unconfined \
        -v "$OUTPUT_DIR:/output" \
        -v "$(pwd):/lfs-builder" \
        -v /dev:/dev \
        -e LFS=/output/image \
        -e MAKEFLAGS="-j$BUILD_THREADS" \
        -e CROSS_COMPILE="$CROSS_COMPILE" \
        -e TARGET_ARCH="$TARGET_ARCH" \
        $DOCKER_IMAGE \
        bash -c "$docker_cmd"

    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        log_success "Build completed successfully!"
    else
        log_error "Build failed with exit code: $exit_code"
        exit $exit_code
    fi
}

# ============================================================================
# POST-BUILD
# ============================================================================

show_results() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════════════════╗"
    echo "║                         BUILD COMPLETE                                    ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════╝"
    echo ""

    local iso_path="$OUTPUT_DIR/lfs-installer.iso"
    local img_path="$OUTPUT_DIR/lfs-mobile.img"

    if [ -f "$iso_path" ]; then
        local iso_size=$(du -h "$iso_path" | cut -f1)
        log_success "ISO created: $iso_path ($iso_size)"
    fi

    if [ -f "$img_path" ]; then
        local img_size=$(du -h "$img_path" | cut -f1)
        log_success "SD card image created: $img_path ($img_size)"
    fi

    echo ""
    echo "📊 Build Summary:"
    echo "  Profile:        $PROFILE"
    echo "  Init System:    $INIT_SYSTEM"
    echo "  Architecture:   $([ "$CROSS_COMPILE" = "true" ] && echo "ARM64" || echo "x86_64")"
    echo "  Output:         $OUTPUT_DIR"
    echo ""

    if [ -f "$iso_path" ]; then
        echo "💿 Writing to USB on macOS:"
        echo "  1. Find your USB drive: diskutil list"
        echo "  2. Unmount it: diskutil unmountDisk /dev/disk2"
        echo "  3. Write ISO: sudo dd if=$iso_path of=/dev/rdisk2 bs=4m status=progress"
        echo ""
    fi

    if [ "$CROSS_COMPILE" = "true" ] || [ "$PROFILE" = "arm64" ] || [ "$PROFILE" = "pinebook" ] || [ "$PROFILE" = "brax3" ]; then
        echo "📱 For ARM64 device:"
        if [ -f "$img_path" ]; then
            echo "  Flash to SD card: dd if=$img_path of=/dev/sdb bs=4M status=progress"
        else
            echo "  Extract and flash the system to your device"
        fi
        echo ""
    fi

    if [ "$PROFILE" = "audio-studio" ] || [ "$PROFILE" = "audio-cli" ]; then
        echo "🎵 Audio Production Features:"
        echo "  - Real-time kernel (PREEMPT_RT)"
        echo "  - JACK2 / PipeWire audio servers"
        echo "  - MIDI tools and LV2 plugins"
        echo "  - Start audio: start-audio"
        echo ""
    fi

    if [ "$PROFILE" = "pinebook" ]; then
        echo "🖥️  Pinebook Specific:"
        echo "  - Keyboard backlight: kbd-backlight up/down"
        echo "  - Battery care: automatic at 80%"
        echo "  - Fan control: automatic"
        echo ""
    fi

    if [ "$PROFILE" = "brax3" ]; then
        echo "📱 Brax3 Smartphone:"
        echo "  - Modem control: brax3-modem {status|enable|disable|sms|call}"
        echo "  - Battery info: brax3-battery"
        echo "  - Display: brax3-display up/down"
        echo ""
    fi

    echo "🔧 Post-installation commands:"
    echo "  - Check updates:   lfs-update check"
    echo "  - Upgrade system:  lfs-update upgrade"
    echo "  - Package manager: lpm list"
    echo ""
}

# ============================================================================
# CLEANUP
# ============================================================================

cleanup() {
    if [ "$1" = "--clean" ]; then
        log_step "Cleaning up..."

        read -p "Remove Docker image $DOCKER_IMAGE? (y/N): " confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            docker rmi "$DOCKER_IMAGE" 2>/dev/null || true
            log_success "Docker image removed"
        fi

        read -p "Remove output directory $OUTPUT_DIR? (y/N): " confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            rm -rf "$OUTPUT_DIR"
            log_success "Output directory removed"
        fi

        rm -f Dockerfile.mac
        log_success "Cleanup complete"
        exit 0
    fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    print_banner

    # Check for clean flag
    if [ "$1" = "--clean" ]; then
        cleanup --clean
    fi

    print_config

    # Prerequisites
    check_docker
    check_disk_space

    # Setup
    prepare_output_directory
    create_dockerfile
    build_docker_image

    # Build
    run_build

    # Results
    show_results

    log_success "macOS LFS Builder finished!"
}

# Run main function
main "$@"