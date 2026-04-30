#!/bin/bash
# macOS LFS Builder using Docker

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Configuration
OUTPUT_DIR="${HOME}/lfs-output"
DOCKER_IMAGE="lfs-builder-mac:latest"

# Check Docker
if ! command -v docker &> /dev/null; then
    log_error "Docker not installed"
    echo "Install Docker Desktop from: https://www.docker.com/products/docker-desktop"
    exit 1
fi

if ! docker info &> /dev/null; then
    log_error "Docker not running"
    echo "Start Docker Desktop from Applications"
    exit 1
fi

log_info "Docker is ready"

# Create output directory
mkdir -p "$OUTPUT_DIR"/{sources,logs,image}

# Build Docker image
log_info "Building Docker image"
cat > Dockerfile.mac << 'EOF'
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

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
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -G sudo builder && \
    echo "builder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER builder
WORKDIR /home/builder

CMD ["/bin/bash"]
EOF

docker build -t $DOCKER_IMAGE -f Dockerfile.mac .

# Build LFS
log_info "Starting LFS build in Docker"

docker run --rm --privileged \
    --cap-add=SYS_ADMIN \
    --security-opt seccomp=unconfined \
    -v "$OUTPUT_DIR:/output" \
    -v "$(pwd):/lfs-builder" \
    -v /dev:/dev \
    -e LFS=/output/image \
    -e MAKEFLAGS="-j$(sysctl -n hw.ncpu)" \
    $DOCKER_IMAGE \
    bash -c "
        cd /lfs-builder
        python3 builder.py --profile xfce --output /output
    "

log_info "Build complete!"
log_info "ISO location: $OUTPUT_DIR/lfs-installer.iso"

# Instructions for writing to USB
echo ""
echo "To write to USB on macOS:"
echo "1. Find your USB drive: diskutil list"
echo "2. Unmount it: diskutil unmountDisk /dev/disk2"
echo "3. Write ISO: sudo dd if=$OUTPUT_DIR/lfs-installer.iso of=/dev/rdisk2 bs=4m status=progress"