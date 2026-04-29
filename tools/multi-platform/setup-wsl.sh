#!/bin/bash
# WSL2 setup for Windows

echo "Setting up WSL2 for LFS building..."

# Check if running in WSL
if ! grep -q Microsoft /proc/version; then
    echo "This script must be run in WSL"
    exit 1
fi

# Update packages
sudo apt update && sudo apt upgrade -y

# Install build dependencies
sudo apt install -y \
    build-essential bison flex gawk texinfo \
    wget curl git python3 python3-pip \
    xorriso isolinux mtools dosfstools \
    parted rsync bc cpio kmod \
    libssl-dev libelf-dev

# Create build directory
mkdir -p ~/lfs-builder
cd ~/lfs-builder

# Clone or copy builder scripts
if [ -d "/mnt/c/Users/$USER/Desktop/lfs-builder" ]; then
    cp -r "/mnt/c/Users/$USER/Desktop/lfs-builder"/* .
else
    echo "Please copy builder scripts to ~/lfs-builder"
fi

echo "WSL2 setup complete!"
echo "Run: python3 builder.py --profile xfce"