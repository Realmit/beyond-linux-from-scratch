#!/bin/bash
# Cross-platform Docker build script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../.."

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }

# Create Dockerfile
cat > Dockerfile.lfs << 'EOF'
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && apt install -y \
    build-essential bison flex gawk texinfo \
    wget curl git python3 python3-pip \
    xorriso isolinux mtools dosfstools \
    parted rsync sudo bc cpio kmod \
    libssl-dev libelf-dev \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m builder && \
    echo "builder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER builder
WORKDIR /home/builder

COPY --chown=builder:builder . /home/builder/lfs-builder

WORKDIR /home/builder/lfs-builder

CMD ["python3", "builder.py", "--profile", "xfce", "--output", "/output"]
EOF

log_info "Building Docker image"
docker build -t lfs-builder -f Dockerfile.lfs .

log_info "Running build"
docker run --rm --privileged \
    -v "$(pwd)/output:/output" \
    lfs-builder

log_info "Build complete! ISO in ./output/"