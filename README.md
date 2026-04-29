# LFS/BLFS Builder - Custom Linux Distribution Builder

## Overview
A complete set of scripts to build a custom Linux From Scratch distribution with desktop environment, capable of creating bootable USB installers from macOS, Linux, or Windows.

## Features
- Complete LFS 12.1 + BLFS 12.1 build system
- Multiple desktop profiles (XFCE, GNOME, Minimal)
- Customizable package selection
- Cross-platform support (Linux, macOS via Docker, Windows via WSL2)
- Automated USB installer creation
- Live CD/USB capability
- User-friendly installation interface

## System Requirements

### Linux
- 50GB free disk space
- 8GB RAM minimum
- 4+ CPU cores
- Ubuntu 22.04+ / Debian 12+ / Fedora 38+

### macOS / Windows
- Docker Desktop (macOS)
- WSL2 with Ubuntu 22.04 (Windows)
- 60GB free space

## Quick Start

```bash
# Clone the repository
git clone https://github.com/yourusername/lfs-builder.git
cd lfs-builder

# Install dependencies (Linux)
sudo ./scripts/host/02-prepare-host.sh

# Build with default profile (XFCE)
python3 builder.py --profile xfce

# Write to USB (when build completes)
python3 builder.py --write-usb /dev/sdX