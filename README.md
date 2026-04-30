## FICHIER: `README.md` (Version complète mise à jour)

```markdown
# LFS/BLFS Builder - Custom Linux Distribution Builder

[![Version](https://img.shields.io/badge/version-4.2.0-blue.svg)](https://github.com/lfs-builder/lfs-builder)
[![License](https://img.shields.io/badge/license-GPLv3-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey.svg)]()

A complete set of scripts to build a custom Linux From Scratch distribution with desktop environment, capable of creating bootable USB installers from macOS, Linux, or Windows.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Build Profiles](#build-profiles)
- [System Requirements](#system-requirements)
- [Quick Start](#quick-start)
- [Installation](#installation)
- [Usage Guide](#usage-guide)
- [Configuration](#configuration)
- [Build Profiles Details](#build-profiles-details)
- [Live USB System](#live-usb-system)
- [Package Manager (LPM)](#package-manager-lpm)
- [System Updater](#system-updater)
- [Security Features](#security-features)
- [Cross-Compilation](#cross-compilation)
- [Troubleshooting](#troubleshooting)
- [Directory Structure](#directory-structure)
- [Contributing](#contributing)
- [License](#license)

## Overview

LFS/BLFS Builder is an automated toolchain that builds a complete Linux distribution from source code using the Linux From Scratch (LFS) and Beyond Linux From Scratch (BLFS) methodologies. It creates bootable ISO images with live system capability, multiple desktop environments, development tools, and security hardening.

## Features

### Core Features
- ✅ Complete LFS 12.2 + BLFS 12.2 build system
- ✅ Live USB "Try before install" capability
- ✅ Automated installer with disk partitioning
- ✅ Cross-platform support (Linux, macOS via Docker, Windows via WSL2)
- ✅ Multiple init systems (systemd, SysV, OpenRC, runit, s6)

### Desktop Environments
- 🖥️ **XFCE 4.20** - Lightweight, fast desktop
- 🖥️ **GNOME 45** - Modern, feature-rich desktop
- 🖥️ **KDE Plasma 6** - Full-featured, customizable desktop
- 🖥️ **LXQt 1.4.0** - Extremely lightweight Qt desktop
- 🖥️ **Minimal** - Command-line only (servers/embedded)

### Development Tools
- ☕ **Java Development** - OpenJDK 21, Maven, Gradle, Tomcat, Jenkins
- 🐳 **Container Support** - Docker, Kubernetes, Podman
- 📦 **Package Manager** - LPM (LFS Package Manager) with upgrade support
- 🔄 **System Updater** - `lfs-update` for system updates and rollbacks

### Security & Privacy
- 🛡️ **Security Hardening** - Kernel hardening, firewall, fail2ban, auditd
- 🔒 **Privacy Tools** - DNSCrypt, WireGuard, Tor, telemetry blocking
- 📊 **Monitoring** - Prometheus, Node Exporter, Netdata, AIDE
- 💾 **Encryption** - Encrypted swap, LUKS support

### Cross-Platform & Embedded
- 📱 **ARM64 Support** - Raspberry Pi, Orange Pi, Pine64
- 🔄 **Cross-Compilation** - Build for ARM64 from x86_64
- 🚀 **U-Boot Integration** - Bootloader support for SBCs

## Build Profiles

| Profile | Desktop | Size | Build Time | RAM | Use Case |
|---------|---------|------|------------|-----|----------|
| **minimal** | None | 1GB | 2h | 256MB | Servers, embedded |
| **xfce** | XFCE | 4GB | 4h | 600MB | Lightweight desktop |
| **lxqt** | LXQt | 2GB | 3h | 500MB | Very lightweight |
| **gnome** | GNOME | 8GB | 8h | 1.5GB | Modern desktop |
| **kde** | KDE Plasma | 10GB | 12h | 1.8GB | Full-featured desktop |
| **java-dev** | XFCE | 10GB | 6h | 2GB | Java development |
| **server** | None | 2GB | 3h | 256MB | Production server |
| **secure** | XFCE | 6GB | 5h | 800MB | Security-focused |
| **full** | GNOME | 20GB | 12h | 2GB | Complete system |
| **arm64** | None | 2GB | 3h | 256MB | ARM64 SBCs |
| **custom** | User-defined | Variable | Variable | Variable | Custom builds |

## System Requirements

### Linux (Native Build)
| Requirement | Minimal | Recommended |
|-------------|---------|-------------|
| **Disk Space** | 50GB | 100GB |
| **RAM** | 8GB | 16GB |
| **CPU Cores** | 4 | 8+ |
| **OS** | Ubuntu 22.04+ | Ubuntu 24.04+ |
| **Architecture** | x86_64 | x86_64 / ARM64 |

### macOS (Docker Build)
| Requirement | Minimal | Recommended |
|-------------|---------|-------------|
| **Disk Space** | 60GB | 100GB |
| **RAM** | 8GB | 16GB |
| **CPU Cores** | 4 | 8+ |
| **Docker** | 24.0+ | Latest |
| **Architecture** | Intel / Apple Silicon | Apple Silicon |

### Windows (WSL2)
| Requirement | Minimal | Recommended |
|-------------|---------|-------------|
| **Disk Space** | 60GB | 100GB |
| **RAM** | 8GB | 16GB |
| **WSL2** | Ubuntu 22.04 | Ubuntu 24.04 |
| **Windows** | Windows 10 2004+ | Windows 11 |

## Quick Start

```bash
# Clone the repository
git clone https://github.com/lfs-builder/lfs-builder.git
cd lfs-builder

# List all available profiles
python3 builder.py --list-profiles

# Build with default profile (XFCE + Live USB)
python3 builder.py

# Build with specific profile
python3 builder.py --profile kde --output ./lfs-kde
python3 builder.py --profile java-dev --output ./lfs-java
python3 builder.py --profile server --output ./lfs-server
python3 builder.py --profile arm64 --config config/build-cross.conf

# Write to USB (after build completes)
python3 builder.py --write-usb /dev/sdX

# Build with security hardening
python3 builder.py --profile secure

# Build full system
python3 builder.py --profile full --output ./lfs-full

# Resume from failed stage
python3 builder.py --resume-from desktop

# Show profile information
python3 builder.py --profile-info java-dev

# Clean build directory
python3 builder.py --clean --output ./lfs-build

# Disable live system (server builds)
python3 builder.py --no-live --profile server

# Override init system
python3 builder.py --init sysv --profile minimal
```

## Installation

### Linux (Native)

```bash
# Install dependencies
sudo apt update
sudo apt install -y build-essential bison flex gawk texinfo \
    wget curl git python3 python3-pip xorriso isolinux \
    mtools dosfstools parted rsync bc cpio kmod \
    libssl-dev libelf-dev

# Clone and build
git clone https://github.com/lfs-builder/lfs-builder.git
cd lfs-builder
python3 builder.py --profile xfce
```

### macOS (Docker)

```bash
# Install Docker Desktop from https://www.docker.com/products/docker-desktop

# Clone and run
git clone https://github.com/lfs-builder/lfs-builder.git
cd lfs-builder
chmod +x mac-lfs-builder.sh
./mac-lfs-builder.sh
```

### Windows (WSL2)

```powershell
# In PowerShell as Administrator
wsl --install -d Ubuntu-22.04

# In WSL2 terminal
sudo apt update && sudo apt upgrade -y
sudo apt install -y build-essential bison flex gawk texinfo \
    wget curl git python3 xorriso isolinux parted rsync

git clone https://github.com/lfs-builder/lfs-builder.git
cd lfs-builder
python3 builder.py --profile xfce
```

## Usage Guide

### Basic Commands

```bash
# Build with default profile
python3 builder.py

# Build with specific profile and output directory
python3 builder.py --profile kde --output ./my-lfs-build

# Use custom configuration
python3 builder.py --config config/my-build.conf

# Resume from failed stage
python3 builder.py --resume-from configure-desktop

# Write ISO to USB
python3 builder.py --write-usb /dev/sdb

# Clean everything
python3 builder.py --clean --output ./lfs-build

# Verbose output
python3 builder.py --verbose
```

### Profile Management

```bash
# List all profiles
python3 builder.py --list-profiles

# Show profile details
python3 builder.py --profile-info secure
python3 builder.py --profile-info arm64

# Build with specific init system
python3 builder.py --profile minimal --init sysv
python3 builder.py --profile server --init openrc

# Disable live system (faster server build)
python3 builder.py --profile server --no-live
```

### Configuration Selection

```bash
# Interactive configuration selector
./tools/config-selector.sh

# Copy specific configuration
cp config/build.conf.java config/build.conf
cp config/build-cross.conf config/build.conf
cp config/build.conf.minimal config/build.conf
```

## Configuration

### Main Configuration (`config/build.conf`)

```json
{
  "lfs_version": "12.2",
  "blfs_version": "12.2",
  "architecture": "x86_64",
  "target_triplet": "x86_64-lfs-linux-gnu",
  "build_threads": 8,

  "init_system": {
    "choice": "systemd",
    "parallel_startup": true,
    "auto_restart": true
  },

  "desktop": {
    "type": "xfce",
    "display_manager": "lightdm",
    "theme": "adwaita",
    "extras": ["firefox", "libreoffice", "gimp", "vlc"]
  },

  "security": {
    "kernel_hardening": true,
    "firewall": {"enabled": true, "allow_ssh": true},
    "fail2ban": {"enabled": true}
  },

  "users": [
    {"name": "lfsuser", "sudo": true, "autologin": true}
  ]
}
```

### Cross-Compilation Configuration (`config/build-cross.conf`)

```json
{
  "architecture": "aarch64",
  "target_triplet": "aarch64-lfs-linux-gnu",
  "cross_compile": true,
  "cross_prefix": "/usr/bin/aarch64-linux-gnu-",
  "qemu_user": "qemu-aarch64-static",
  
  "bootloader": {
    "type": "uboot",
    "uboot_board": "rpi_4"
  }
}
```

## Build Profiles Details

### XFCE Profile
Lightweight desktop perfect for older hardware or users who prefer speed.

```bash
python3 builder.py --profile xfce
```
- **Desktop**: XFCE 4.20
- **Panel**: Customizable with plugins
- **File Manager**: Thunar
- **Terminal**: XFCE Terminal
- **Memory**: ~600MB

### GNOME Profile
Modern, polished desktop with extensive application suite.

```bash
python3 builder.py --profile gnome
```
- **Desktop**: GNOME 45
- **Display Manager**: GDM with Wayland
- **File Manager**: Nautilus
- **Terminal**: GNOME Terminal
- **Memory**: ~1.5GB

### KDE Plasma Profile
Full-featured desktop with maximum customization.

```bash
python3 builder.py --profile kde
```
- **Desktop**: KDE Plasma 6
- **Display Manager**: SDDM
- **File Manager**: Dolphin
- **Terminal**: Konsole
- **Memory**: ~1.8GB
- **Build Time**: 8-12 hours

### LXQt Profile
Extremely lightweight Qt-based desktop.

```bash
python3 builder.py --profile lxqt
```
- **Desktop**: LXQt 1.4.0
- **Window Manager**: Openbox
- **File Manager**: PCManFM-Qt
- **Terminal**: QTerminal
- **Memory**: ~500MB

### Java Development Profile
Complete Java development environment.

```bash
python3 builder.py --profile java-dev
```
- **JDK**: OpenJDK 21.0.8 LTS
- **Build Tools**: Maven 3.9.9, Gradle 8.13
- **Servers**: Tomcat 10.1.39, Jenkins 2.492.2
- **Containers**: Docker 27.4.1, kubectl 1.32.3
- **Node.js**: 22.14.0 LTS

### Server Profile
Production-optimized server configuration.

```bash
python3 builder.py --profile server
```
- **Kernel**: Optimized (TCP BBR, tuned sysctl)
- **Security**: Hardened SSH, firewall, fail2ban
- **Monitoring**: Prometheus node_exporter, Netdata
- **Logging**: Centralized rsyslog
- **Backup**: Automated daily backups

### Secure Profile
Security-hardened desktop with privacy tools.

```bash
python3 builder.py --profile secure
```
- **Hardening**: Kernel hardening, SELinux/AppArmor
- **Firewall**: nftables with default deny
- **Intrusion Detection**: AIDE, rkhunter, Lynis
- **Privacy**: DNSCrypt, WireGuard, Tor
- **Audit**: Full auditd configuration

### ARM64 Profile
For Raspberry Pi and ARM64 single-board computers.

```bash
python3 builder.py --profile arm64 --config config/build-cross.conf
```
- **Architecture**: aarch64
- **Bootloader**: U-Boot
- **Boards**: Raspberry Pi 4/5, Orange Pi, Pine64
- **Output**: SD card image (.img)
- **Cross-Compile**: From x86_64 host

### Full Profile
Complete system with everything enabled.

```bash
python3 builder.py --profile full
```
- **Size**: ~20GB
- **Build Time**: ~12 hours
- **Includes**: All desktop environments + Java dev + Security + Privacy

## Live USB System

Your built ISO includes a complete live system:

### Boot Menu Options
1. **Try LFS Linux (Live mode)** - Boot in RAM, no disk writes
2. **Try LFS Linux (with Persistence)** - Save changes on USB
3. **Install LFS Linux** - Permanent installation
4. **Memory Test** - Diagnostic tool
5. **Rescue Mode** - System recovery

### Creating Persistence

```bash
# After writing ISO to USB, create persistence partition
sudo create-persistence.sh /dev/sdb 4096  # 4GB persistence

# With custom label
sudo create-persistence.sh -l MYSTORAGE /dev/sdc

# Remove persistence
sudo create-persistence.sh --remove /dev/sdb
```

## Package Manager (LPM)

LPM (LFS Package Manager) is included for package management.

### Basic Commands

```bash
# Update package database
lpm update

# Install packages
lpm install firefox
lpm install /path/to/package.lpm

# List installed packages
lpm list

# Search packages
lpm search "java"

# Remove packages
lpm remove firefox

# Create package from installed files
lpm create myapp 1.0.0
```

### Upgrade Commands

```bash
# List outdated packages
lpm list-outdated

# Upgrade single package
lpm upgrade firefox

# Upgrade all packages
lpm upgrade
```

## System Updater

`lfs-update` manages system updates and rollbacks.

### Commands

```bash
# Check for available updates
lfs-update check

# Show system status
lfs-update status

# Perform full system upgrade
lfs-update upgrade

# Rollback to previous state
lfs-update rollback

# Clean old backups
lfs-update clean
```

### Automatic Updates
- Daily update checks via cron or systemd timer
- Email notifications when updates available
- Automatic backup before upgrades
- Last 5 backups kept by default

## Security Features

### Kernel Hardening
- ASLR improvements
- Kernel pointer restriction
- BPF JIT hardening
- ptrace scope restriction

### Firewall (nftables)
- Default deny policy
- Stateful inspection
- Rate limiting
- Logging of dropped packets

### Fail2ban
- SSH brute force protection
- Customizable ban times
- Email alerts

### Intrusion Detection
- AIDE (file integrity monitoring)
- Daily security scans
- Rootkit detection (rkhunter)
- Security auditing (Lynis)

### User Hardening
- Password quality enforcement
- Login delay after failures
- Account lockout after 5 attempts
- Root SSH login disabled

## Cross-Compilation

Build for ARM64 from x86_64 host.

### Prerequisites

```bash
# Install cross-compilation toolchain
sudo apt install -y gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu qemu-user-static

# For ARM32
sudo apt install -y gcc-arm-linux-gnueabihf binutils-arm-linux-gnueabihf
```

### Build for ARM64

```bash
# Using ARM64 profile
python3 builder.py --profile arm64 --config config/build-cross.conf

# Custom board selection
BOARD=rpi_5 python3 builder.py --profile arm64 --config config/build-cross.conf

# Custom output
python3 builder.py --profile arm64 --config config/build-cross.conf --output ./lfs-arm64

# Create SD card image
python3 builder.py --profile arm64 --config config/build-cross.conf
# Output: lfs-arm64.img
```

### Supported Boards

| Board | Config | Status |
|-------|--------|--------|
| Raspberry Pi 4 | `BOARD=rpi_4` | ✅ Full |
| Raspberry Pi 5 | `BOARD=rpi_5` | ✅ Full |
| Orange Pi PC | `BOARD=orangepi_pc` | 🧪 Testing |
| Pine64 | `BOARD=pine64` | 🧪 Testing |

## Troubleshooting

### Common Issues

#### Build fails at toolchain stage
```bash
# Check log
cat lfs-build/logs/toolchain.log

# Resume from failed stage
python3 builder.py --resume-from toolchain
```

#### Low disk space
```bash
# Clean build directory
python3 builder.py --clean

# Use external drive
export LFS_BUILD_DIR=/mnt/external-drive/lfs-build
```

#### Java download fails
```bash
# URLs are automatically updated to Eclipse Temurin
# Check network connectivity
curl -I https://github.com/adoptium/
```

#### Live USB boot issues
```bash
# Verify ISO checksum
sha256sum lfs-installer.iso

# Check USB device
lsblk
sudo fdisk -l /dev/sdb

# Re-write with dd
sudo dd if=lfs-installer.iso of=/dev/sdb bs=4M status=progress
```

#### Cross-compilation issues
```bash
# Verify cross-toolchain
aarch64-linux-gnu-gcc --version

# Check QEMU registration
update-binfmts --display

# Manual QEMU setup
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
```

## Directory Structure

```
lfs-builder/
├── builder.py                 # Main orchestrator (v4.2.0)
├── mac-lfs-builder.sh         # macOS Docker build script
├── Dockerfile.mac             # macOS Docker configuration
├── config/
│   ├── build.conf             # Main configuration
│   ├── build.conf.minimal     # Minimal server config
│   ├── build-cross.conf       # Cross-compilation config
│   ├── build-java.conf        # Java-optimized config
│   ├── kernel-config          # x86_64 kernel config
│   ├── kernel-config-arm64    # ARM64 kernel config
│   ├── u-boot.config          # U-Boot configuration
│   ├── desktop.conf           # Desktop settings
│   ├── init.conf              # Init system config
│   ├── security.conf          # Security settings
│   ├── lpm.conf               # Package manager config
│   └── packages.conf.json     # Package definitions
├── scripts/
│   ├── host/                  # Host preparation scripts
│   ├── lfs/                   # LFS build scripts
│   ├── blfs/                  # BLFS build scripts
│   ├── common/                # Common utilities
│   └── final/                 # ISO creation scripts
├── profiles/
│   ├── minimal/               # Minimal profile
│   ├── xfce/                  # XFCE profile
│   ├── gnome/                 # GNOME profile
│   ├── kde/                   # KDE Plasma profile
│   ├── lxqt/                  # LXQt profile
│   ├── java-dev/              # Java development profile
│   ├── server/                # Server profile
│   ├── secure/                # Security-hardened profile
│   ├── full/                  # Complete system
│   ├── arm64/                 # ARM64 profile
│   └── custom/                # Custom profile template
├── packages/
│   ├── sources.list           # Package download URLs
│   ├── custom-scripts/        # Custom installation scripts
│   └── md5sums                # Checksum verification
├── tools/
│   ├── multi-platform/        # Platform-specific tools
│   ├── build-matrix.sh        # Multi-arch build automation
│   └── config-selector.sh     # Interactive config selection
├── README.md                  # This file
├── CHANGELOG.md               # Version history
├── CONTRIBUTING.md            # Contribution guidelines
└── ADVANCED.md                # Advanced usage guide
```

## Post-Installation

After installation, log into your new LFS system:

```bash
# Default credentials
Username: lfsuser
Password: lfsuser123

# Root password
root123
```

### First Boot

The system will automatically:
1. Detect hardware (CPU, RAM, GPU)
2. Configure network via DHCP
3. Set up graphics drivers
4. Create user directories
5. Enable appropriate services

### Post-Install Commands

```bash
# System update
lfs-update check
lfs-update upgrade

# Install new packages
lpm search firefox
lpm install firefox

# Service management
svc start sshd
svc status tomcat

# System status
status.sh

# Backup system
backup-system.sh
```

## Contributing

Please see [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

### Quick Contribution Guide

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'feat: add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Commit Convention

```
feat(scope): add new feature
fix(scope): fix bug
docs(scope): update documentation
refactor(scope): code refactor
test(scope): add tests
chore(scope): maintenance tasks
```

## Support

- 📖 **Documentation**: [ADVANCED.md](ADVANCED.md)
- 📝 **Changelog**: [CHANGELOG.md](CHANGELOG.md)
- 🐛 **Issues**: [GitHub Issues](https://github.com/lfs-builder/lfs-builder/issues)
- 💬 **Discussions**: [GitHub Discussions](https://github.com/lfs-builder/lfs-builder/discussions)

## Acknowledgments

- [Linux From Scratch](https://www.linuxfromscratch.org/) - LFS and BLFS books
- [Adoptium](https://adoptium.net/) - OpenJDK builds
- [XFCE](https://www.xfce.org/) - Lightweight desktop
- [GNOME](https://www.gnome.org/) - Modern desktop
- [KDE](https://kde.org/) - Plasma desktop
- [LXQt](https://lxqt-project.org/) - Qt lightweight desktop

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

---

## Quick Reference

### Build Commands
```bash
python3 builder.py --list-profiles
python3 builder.py --profile xfce
python3 builder.py --profile secure --init sysv
python3 builder.py --profile arm64 --config config/build-cross.conf
python3 builder.py --write-usb /dev/sdb
python3 builder.py --clean
```

### System Commands (on built system)
```bash
lfs-update status
lfs-update upgrade
lpm list
lpm upgrade firefox
svc start tomcat
status.sh
```

### Useful Aliases (on built system)
```bash
java-build      # mvn clean compile
gradle-build    # ./gradlew build
tomcat-start    # systemctl start tomcat
proj            # cd ~/projects
```

---

**Built with ❤️ for the LFS community**
```