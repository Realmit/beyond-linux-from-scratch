# Changelog

All notable changes to the LFS/BLFS Builder project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [4.0.0] - 2026-04-30

### Added
- **Live System Support** (Integrated in `14-create-installer.sh`)
  - Complete "Try before install" live mode
  - SquashFS compressed root filesystem
  - RAM-based operation (no disk writes)
  - Persistence support for saving changes on USB
  - Live initramfs with overlay filesystem
  - Boot menu options: Live, Live with Persistence, Install, Rescue
  - `create-persistence.sh` tool for adding persistence to USB
  - Automatic hardware detection in live mode

- **System Update/Upgrade Manager** (`18-system-updater.sh`)
  - `lfs-update check` - Check for available system updates
  - `lfs-update upgrade` - Full system upgrade with backup
  - `lfs-update rollback` - Rollback to previous system state
  - `lfs-update status` - Show system version and package status
  - Automatic backup before any upgrade
  - Daily automatic update checks (cron/systemd timer)
  - Email notifications for available updates
  - Configurable backup retention (keeps last 5 backups)

- **Package Upgrade Commands** (`19-package-updater.sh`)
  - `lpm upgrade <package>` - Upgrade single package
  - `lpm upgrade` - Upgrade all outdated packages
  - `lpm list-outdated` - List packages with available updates
  - Version comparison against repositories
  - Repository database synchronization

- **New Configuration Options**
  - `system_updater` section in build.conf
    - `enabled`, `auto_check`, `backup_before_upgrade`, `keep_backups`, `rollback_support`
  - `live_system` section in build.conf
    - `enabled`, `squashfs_compression`, `persistence_support`, `default_boot`

- **New Command Line Options**
  - `--version` - Display builder version
  - `--no-live` - Disable live system creation (server builds)
  - Enhanced `--profile-info` with live and updater status

- **New Profile Features**
  - All desktop profiles now include live system support
  - System updater enabled by default for desktop profiles
  - Profile info shows live system and updater status

### Changed
- **builder.py** upgraded to v4.0.0
  - Added `LIVE_SYSTEM` and `SYSTEM_UPDATER` environment variables
  - New build stages: `system-updater`, `package-updater`
  - Improved USB device listing with size and model
  - Better error recovery with staged backups
  - Version display in build info and command line

- **14-create-installer.sh** Enhanced with live system
  - Squashfs creation of root filesystem
  - Separate live initramfs with overlay support
  - Persistence partition detection and mounting
  - Dual boot menu (Live/Install)
  - Copy custom scripts to live environment

- **Profile Manager** Updated
  - Added `live_system` and `system_updater` flags to all profiles
  - Size estimates adjusted for live system overhead
  - Default profile now uses live boot by default

- **Configuration Defaults**
  - LFS version: 12.2
  - BLFS version: 12.2
  - Kernel version: 6.12.10
  - Java version: 21.0.8
  - Updated package versions throughout

### Fixed
- Squashfs compression now properly excludes temporary directories
- Live initramfs detection of USB media
- Persistence partition label detection
- Boot menu timeout and default selection
- ISO size calculation in build summary
- Checksum generation for final ISO

### Security
- Live system runs with restricted kernel parameters
- Persistence partition uses encryption-ready filesystem
- Automatic audit of live session activities

## [3.0.0] - 2026-04-15

### Added
- **Security Hardening Module** (`15-security-hardening.sh`)
  - Kernel hardening with sysctl optimizations
  - Firewall setup (nftables/iptables with fallback)
  - Fail2ban integration for brute force protection
  - Audit system (auditd) with file integrity monitoring
  - AppArmor mandatory access control (optional)
  - Daily security scans with cron
  - Rootkit Hunter (rkhunter) integration
  - Lynis security auditing tool
  - AIDE (Advanced Intrusion Detection Environment)
  - Password quality enforcement (pwquality)
  - User account hardening (login delays, lockouts)
  - Encrypted swap support
  - Daily security reports via email

- **Privacy Tools Module** (`16-privacy-tools.sh`)
  - WireGuard VPN support
  - Tor anonymization network
  - DNSCrypt for encrypted DNS
  - Firefox privacy preset configuration
  - Telemetry blocking across applications
  - Core dump disabling
  - History sanitization for root user
  - /tmp clearing on boot

- **Init System Support** (`06a-init-system.sh`)
  - **systemd** - Modern init with full service management
  - **SysV init** - Traditional UNIX init scripts
  - **OpenRC** - Dependency-based init (Gentoo style)
  - **runit** - Simple service supervision
  - **s6** - Small supervision suite
  - Parallel service startup support
  - Auto-restart on failure capability
  - Configurable runlevels/targets

- **Service Management Abstraction** (`06b-service-management.sh`)
  - Unified `svc` command for all init systems
  - Service aliases for consistent UX
  - Cross-platform service detection
  - Status, start, stop, restart, enable, disable commands

- **Custom Scripts System**
  - `theme-setup.sh` - Automatic font, icon, and GTK theme installation
  - `first-boot.sh` - First boot hardware detection and system configuration
  - Automatic first-boot service for systemd and SysV init
  - Theme persistence across user accounts

- **New Build Profiles**
  - `secure` - Security-hardened system with privacy tools
  - `full` - Complete system with all features enabled
  - Enhanced profile descriptions with security indicators

- **Extended Configuration Files**
  - `build-cross.conf` - Cross-compilation configuration for ARM, ARM64, RISC-V
  - `build-java.conf` - Java-optimized build configuration
  - `build.conf.minimal` - Lightweight server configuration
  - `init.conf` - Init system selection and tuning
  - `lpm.conf` - Package manager configuration
  - `packages.conf` - Package definitions with categories
  - `packages.conf.json` - JSON format package definitions
  - `security.conf` - Comprehensive security settings

- **Profile Variants**
  - `gnome` - Full GNOME desktop environment
  - `kde` - KDE Plasma desktop (optional)
  - `lxqt` - Lightweight LXQt desktop
  - `server` - Optimized for server workloads
  - `custom` - User-defined profile template

- **Command Line Options**
  - `--init` - Override init system choice at build time
  - `--list-profiles` - Show all available build profiles
  - `--profile-info` - Display detailed profile information
  - `--clean` - Remove build directory
  - `--verbose` - Enable detailed logging

- **Helper Tools**
  - `build-matrix.sh` - Multi-architecture build automation
  - `config-selector.sh` - Interactive configuration selection
  - Docker build support for macOS (`mac-lfs-builder.sh`, `Dockerfile.mac`)
  - WSL2 setup script for Windows

- **Documentation**
  - `README.md` - Complete project documentation
  - `CHANGELOG.md` - Version history (this file)
  - `CONTRIBUTING.md` - Contribution guidelines
  - `ADVANCED.md` - Advanced usage and optimization guide

### Changed
- **builder.py** upgraded to v3.0.0
  - Profile manager now includes security flags
  - Added resume capability from failed stages
  - Parallel source downloads (4 threads)
  - Checksum verification for all sources
  - USB device auto-detection
  - Build info JSON generation

- **14-create-installer.sh** Enhanced
  - Custom scripts integration (`theme-setup.sh`, `first-boot.sh`)
  - First-boot service for systemd and SysV init
  - EFI boot support
  - Automatic SHA256 checksum generation

- **Configuration System**
  - `build.conf` now includes comprehensive security section
  - Split configuration into specialized files

- **Package Sources** (`packages/sources.list`)
  - Updated to LFS 12.2 (Linux 6.12.10, GCC 14.2.0, Glibc 2.40)
  - XFCE 4.20, LightDM 1.32.1
  - Firefox 128.4.0esr, LibreOffice 24.8.4
  - JDK 21.0.8, Maven 3.9.9, Gradle 8.13

### Fixed
- Service detection across different init systems
- Java download URL issues (Eclipse Temurin)
- ISO creation with proper UEFI/BIOS dual boot support

### Security
- Hardened kernel parameters applied by default
- SSH root login disabled
- Daily vulnerability scanning

## [2.0.0] - 2026-04-15

### Added
- **Java Development Environment** (`12-install-java-dev.sh`)
  - OpenJDK 21.0.8 (Eclipse Temurin)
  - Maven 3.9.9, Gradle 8.13
  - Apache Tomcat 10.1.39, Jenkins 2.492.2
  - Node.js 22.14.0, Docker 27.4.1, kubectl 1.32.3
  - JMeter 5.6.3, Allure 2.32.0
  - JVM optimizations and demo projects

- **LPM Package Manager** (`13-create-package-manager.sh`)
  - `lpm` command with install, remove, list, search, info, create
  - Binary package format (.lpm)
  - Package database tracking
  - Repository system with multiple sources

- **Base Packages Creation** (`14-create-base-packages.sh`)
  - Pre-built packages for Java, Maven, Gradle, Tomcat, Node.js, Docker, Jenkins
  - Local repository generation

- **Desktop Configuration Enhancements**
  - XFCE panel customization
  - Theme and icon presets (Papirus, Arc-Dark)
  - Keyboard shortcuts
  - Auto-login configuration

- **New Build Profile**
  - `java-dev` - Java development environment with XFCE

### Changed
- **builder.py** upgraded to v2.0.0
  - Added profile manager class
  - Parallel downloads
  - Build resume capability

### Fixed
- Java download URL issues
- Tomcat and Jenkins service configurations

## [1.0.0] - 2025-12-20

### Added
- Initial release of LFS/BLFS Builder

- **Core Build System**
  - `builder.py` - Main orchestrator
  - LFSConfig configuration management
  - ScriptExecutor for build stages
  - USBWriter for ISO deployment

- **Host Preparation Scripts** (`scripts/host/`)
  - `01-check-host.sh` - System verification
  - `02-prepare-host.sh` - Environment setup
  - `03-create-disk-image.sh` - Disk image creation
  - `04-build-toolchain.sh` - Cross-compilation toolchain

- **LFS Core Scripts** (`scripts/lfs/`)
  - `05-build-lfs-basic.sh` - Base system
  - `06-build-lfs-system.sh` - Complete LFS
  - `07-configure-lfs.sh` - System configuration

- **BLFS Scripts** (`scripts/blfs/`)
  - `08-build-blfs-base.sh` - BLFS core
  - `09-build-desktop.sh` - Desktop environment
  - `10-build-applications.sh` - Applications
  - `11-configure-desktop.sh` - Desktop tuning

- **Finalization Scripts** (`scripts/final/`)
  - `12-create-initramfs.sh` - Initramfs
  - `13-create-bootloader.sh` - GRUB
  - `14-create-installer.sh` - ISO creation

- **Build Profiles**
  - `minimal` - CLI only, 1GB
  - `xfce` - XFCE desktop, 4GB
  - `gnome` - GNOME desktop, 8GB

- **Application Support**
  - Firefox, LibreOffice, GIMP, VLC, Thunar

- **Cross-Platform Support**
  - Linux native, macOS Docker, Windows WSL2

### Notes
- LFS version: 12.1
- Kernel version: 6.6.14
- Minimum RAM: 8GB
- Required disk: 50GB

## [Unreleased]

### Planned Features
- Graphical package manager frontend (GTK/Qt)
- Binary repository with pre-built packages
- Full disk encryption with LUKS
- Secure boot support (Shim + GRUB)
- Flatpak/Snap support
- Wayland compositor support (Sway, Hyprland)
- Automated testing framework (pytest)
- Build cache for faster rebuilds (ccache)
- System backup and restore utilities
- GUI system configuration tool (LFS Control Center)
- Network manager with VPN support
- Printing system (CUPS) integration
- Gaming optimizations (Wine, Proton, Steam)
- Real-time kernel option (PREEMPT_RT)
- Embedded systems profile (Raspberry Pi, ARM64)
- RISC-V architecture support
- ZFS filesystem support
- Btrfs snapshots and rollback
- System monitoring dashboard (Cockpit)

---

## Version History

| Version | Date | Status | Key Features |
|---------|------|--------|--------------|
| 4.0.0 | 2026-04-30 | ✅ Current | Live USB, System Updater, Package Updater |
| 3.0.0 | 2026-04-15 | ✅ Stable | Security Hardening, Privacy Tools, Init Systems |
| 2.0.0 | 2026-04-15 | ✅ Stable | Java Dev Environment, LPM Package Manager |
| 1.0.0 | 2025-12-20 | ✅ Stable | Base LFS/BLFS with XFCE |

---

## Upgrade Notes

### From 3.0.0 to 4.0.0
1. Update `builder.py` to v4.0.0
2. Add `system_updater` and `live_system` sections to `build.conf`
3. Run new scripts: `18-system-updater.sh`, `19-package-updater.sh`
4. Rebuild ISO for live system support: `python3 builder.py --profile secure`

### From 2.0.0 to 3.0.0
1. Add `security` section to `build.conf`
2. Run security hardening scripts
3. Configure init system in `config/init.conf`

### From 1.0.0 to 2.0.0
1. Add Java development sources to `packages/sources.list`
2. Run Java installation scripts

### Fresh Installation
```bash
# Clone repository
git clone https://github.com/lfs-builder/lfs-builder.git
cd lfs-builder

# Build with live system support
python3 builder.py --profile full

# Write to USB
python3 builder.py --write-usb /dev/sdX

# Boot from USB and select "Try LFS Linux"