# Changelog

All notable changes to the LFS/BLFS Builder project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.0.0] - 2026-04-30

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
  - Support for systemd, sysv, openrc, runit, s6

- **Configuration Options**
  - `security` section in build.conf with 30+ hardening options
  - Kernel hardening parameters
  - Firewall rules configuration
  - Fail2ban jail settings
  - Audit monitoring paths
  - User hardening policies
  - Encryption settings
  - HIDS configuration
  - Privacy tools toggles
  - Init system behavior tuning

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
  - Added security and privacy environment variables
  - Extended build stages with security modules
  - Improved error handling for security scripts
  - Better logging for security events
  - Profile manager now includes security flags
  - Added resume capability from failed stages
  - Parallel source downloads (4 threads)
  - Checksum verification for all sources
  - USB device auto-detection
  - Build info JSON generation

- **14-create-installer.sh** Completely rewritten
  - Added custom scripts integration (`theme-setup.sh`, `first-boot.sh`)
  - First-boot service for systemd and SysV init
  - Enhanced installer with better UI and pre-installation checks
  - EFI boot support
  - Automatic SHA256 checksum generation
  - Live system boot option
  - Improved error handling and logging

- **Configuration System**
  - `build.conf` now includes comprehensive security section
  - Default config includes sensible security defaults
  - Non-intrusive privacy settings by default
  - Split configuration into specialized files

- **Profile Manager**
  - Profiles now specify security_hardening and privacy_tools flags
  - Size estimates updated for security tools
  - Build time estimates reflect additional modules
  - Support for 8+ build profiles

- **Package Sources** (`packages/sources.list`)
  - Updated all packages to latest stable versions (April 2026)
  - LFS 12.2: Linux 6.12.10, GCC 14.2.0, Glibc 2.40
  - BLFS 12.2: GLib 2.82.4, GTK+ 3.24.48
  - XFCE 4.20, LightDM 1.32.1
  - Firefox 128.4.0esr, LibreOffice 24.8.4, VLC 3.0.21, GIMP 2.10.38
  - JDK 21.0.8, Maven 3.9.9, Gradle 8.13, Tomcat 10.1.39, Node.js 22.14.0
  - Docker 27.4.1, kubectl 1.32.3, Jenkins 2.492.2
  - Security tools: Fail2ban 1.1.0, Lynis 3.1.3, rkhunter 1.4.6

### Fixed
- Timeout handling for long-running security scans
- Proper cleanup of temporary security files
- Service detection across different init systems
- Permission issues with audit logs
- Java download URL issues (now using Eclipse Temurin)
- Tomcat service configuration for systemd
- Permission issues with Jenkins service
- Path resolution in chroot environment
- ISO creation with proper UEFI/BIOS dual boot support

### Security
- Hardened kernel parameters applied by default
- Firewall enabled on secure profiles
- SSH root login disabled by default
- Failed login tracking and locking
- File integrity baseline created at first boot
- Daily vulnerability scanning scheduled
- Encrypted swap to prevent memory leaks
- Package checksum verification
- Source validation before build
- Secure service file permissions

### Deprecated
- Direct Java download from Oracle (404 errors)
- Old LFS 12.1 package versions

### Removed
- Outdated package URLs from sources.list

## [2.0.0] - 2026-04-15

### Added
- **Java Development Environment** (`12-install-java-dev.sh`)
  - OpenJDK 21.0.6 (Eclipse Temurin distribution)
  - Maven 3.9.6 build automation
  - Gradle 8.5 build tool
  - Apache Tomcat 10.1.16 servlet container
  - Jenkins 2.440 CI/CD server
  - Node.js 20.11.0 runtime
  - Docker 24.0.7 container runtime
  - kubectl 1.29.0 Kubernetes client
  - JMeter 5.6.3 performance testing
  - Allure 2.25.0 test reporting
  - JVM optimizations and tuning
  - Demo projects for quick start

- **LPM Package Manager** (`13-create-package-manager.sh`)
  - `lpm` command with install, remove, list, search, info, update, create functions
  - Binary package format (.lpm)
  - Source package building from PKGBUILD
  - Package database tracking
  - Repository system with multiple sources
  - Dependency resolution (planned)
  - Package signing (planned)

- **Base Packages Creation** (`14-create-base-packages.sh`)
  - Pre-built packages for Java, Maven, Gradle, Tomcat, Node.js, Docker, Jenkins
  - Local repository generation
  - Package metadata creation

- **Desktop Configuration Enhancements**
  - XFCE panel customization
  - Theme and icon presets
  - Keyboard shortcut defaults
  - Auto-login configuration
  - Startup application management

- **New Build Profiles**
  - `java-dev` - Java development environment with XFCE
  - Enhanced profile system with package lists

- **Command Line Options**
  - `--list-profiles` - Show all available build profiles
  - `--profile-info` - Display detailed profile information
  - `--clean` - Remove build directory
  - `--verbose` - Enable detailed logging

### Changed
- **builder.py** upgraded to v2.0.0
  - Added profile manager class
  - Parallel source downloads (4 threads)
  - Checksum verification for all sources
  - Build resume capability from failed stages
  - USB device auto-detection
  - macOS and Windows platform support
  - Build info JSON generation

- **Script Organization**
  - Restructured BLFS scripts (08-11)
  - Added Java and Package Manager stages (12-14)
  - Improved script error handling

### Fixed
- Java download URL issues (now using Eclipse Temurin)
- Tomcat service configuration for systemd
- Permission issues with Jenkins service
- Path resolution in chroot environment

### Security
- Package checksum verification
- Source validation before build
- Secure service file permissions

### Deprecated
- Direct Java download from Oracle (404 errors)

## [1.0.0] - 2025-12-20

### Added
- Initial release of LFS/BLFS Builder

- **Core Build System**
  - `builder.py` - Main orchestrator with stage management
  - LFSConfig class for configuration handling
  - ScriptExecutor for build stage execution
  - USBWriter for ISO deployment

- **Host Preparation Scripts** (`scripts/host/`)
  - `01-check-host.sh` - System requirements verification
  - `02-prepare-host.sh` - Build environment setup
  - `03-create-disk-image.sh` - Disk image creation
  - `04-build-toolchain.sh` - Cross-compilation toolchain

- **LFS Core Scripts** (`scripts/lfs/`)
  - `05-build-lfs-basic.sh` - Base LFS system
  - `06-build-lfs-system.sh` - Complete LFS build
  - `07-configure-lfs.sh` - System configuration

- **BLFS Scripts** (`scripts/blfs/`)
  - `08-build-blfs-base.sh` - BLFS core packages
  - `09-build-desktop.sh` - Desktop environment
  - `10-build-applications.sh` - Common applications
  - `11-configure-desktop.sh` - Desktop tuning

- **Finalization Scripts** (`scripts/final/`)
  - `12-create-initramfs.sh` - Initramfs generation
  - `13-create-bootloader.sh` - GRUB configuration
  - `14-create-installer.sh` - Bootable ISO creation

- **Utility Functions** (`scripts/common/`)
  - `utils.sh` - Common bash utilities
  - `chroot-utils.sh` - Chroot environment helpers
  - `error-handler.sh` - Error trapping and recovery

- **Build Profiles**
  - `minimal` - Command-line only, 1GB, 2 hours
  - `xfce` - XFCE desktop, 4GB, 4 hours
  - `gnome` - GNOME desktop, 8GB, 8 hours

- **Configuration Files**
  - `build.conf` - JSON-based configuration
  - `kernel-config` - Linux kernel configuration
  - `packages.conf` - Package definitions
  - `desktop.conf` - Desktop environment settings

- **Package Sources** (`packages/`)
  - `sources.list` - Download URLs for all packages
  - `custom-scripts/post-install.sh` - Post-installation hooks

- **Desktop Customization** (`profiles/`)
  - XFCE panel configuration
  - GTK theme settings
  - LightDM autologin setup
  - Default wallpaper installation
  - Keyboard shortcuts

- **Application Support**
  - Firefox web browser
  - LibreOffice suite
  - GIMP image editor
  - VLC media player
  - Thunar file manager
  - XFCE terminal

- **Cross-Platform Support**
  - Linux native build
  - macOS Docker build (`mac-lfs-builder.sh`)
  - Windows WSL2 support

- **USB Deployment**
  - ISO creation with isolinux
  - UEFI and BIOS boot support
  - Interactive installer script
  - USB writing utilities

### Security (Base)
- Basic filesystem permissions
- User/group isolation
- SSH daemon with key authentication
- Firewall rules template

### Known Issues
- Long build times (4-12 hours depending on profile)
- Large disk space requirement (50+ GB)
- Some applications require manual configuration

### Notes
- LFS version: 12.1
- BLFS version: 12.1
- Kernel version: 6.6.14
- Minimum RAM: 8GB
- Recommended CPU: 4+ cores

## [Unreleased]

### Planned Features
- Graphical package manager frontend (GTK/Qt)
- System update mechanism (`lpm upgrade`)
- Package dependency resolution
- Container (Docker/Podman) integration
- Flatpak/Snap support
- Wayland compositor support (Sway, Hyprland)
- Full disk encryption with LUKS
- Secure boot support (Shim + GRUB)
- Automated testing framework (pytest)
- Build cache for faster rebuilds (ccache integration)
- Binary repository with pre-built packages
- System backup and restore utilities
- GUI system configuration tool (LFS Control Center)
- Network manager with VPN support
- Printing system (CUPS) integration
- Multimedia codec pack (ffmpeg, gstreamer)
- Gaming optimizations (Wine, Proton, Steam)
- Real-time kernel option (PREEMPT_RT)
- Embedded systems profile (Raspberry Pi, ARM)
- Cloud image generation (AWS AMI, Azure, GCP)
- Raspberry Pi 4/5 and ARM64 support
- RISC-V architecture support
- ZFS filesystem support
- Btrfs snapshots and rollback
- User session management (elogind)
- Bluetooth audio (PipeWire)
- System monitoring dashboard (Cockpit)

---

## Version History

| Version | Date | Status | Description |
|---------|------|--------|-------------|
| 3.0.0 | 2026-04-30 | ✅ Current | Security hardening, privacy tools, init system choice, custom scripts |
| 2.0.0 | 2026-04-15 | ✅ Stable | Java development environment, LPM package manager |
| 1.0.0 | 2025-12-20 | ✅ Stable | Initial release, base LFS/BLFS with XFCE |

---

## Upgrade Notes

### From 2.0.0 to 3.0.0
1. Add `security` section to `build.conf`
2. Install additional security tools if using `secure` or `full` profile
3. Update builder.py to v3.0.0
4. Run security hardening scripts on existing systems (`scripts/blfs/15-security-hardening.sh`)
5. Install privacy tools if needed (`scripts/blfs/16-privacy-tools.sh`)
6. Configure init system choice in `config/init.conf`

### From 1.0.0 to 2.0.0
1. Add Java development files to `packages/sources.list`
2. Create `profiles/java-dev` directory
3. Update builder.py to v2.0.0
4. Install Java development environment (`scripts/blfs/12-install-java-dev.sh`)
5. Initialize package manager (`scripts/blfs/13-create-package-manager.sh`)

### Fresh Installation
```bash
# Clone repository
git clone https://github.com/lfs-builder/lfs-builder.git
cd lfs-builder

# Copy configuration
cp config/build.conf.example config/build.conf

# Edit configuration
vim config/build.conf

# Start build
python3 builder.py --profile secure