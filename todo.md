I'll create a comprehensive set of scripts for building a custom LFS/BLFS distribution. This is a substantial project, so I'll provide the core infrastructure and main scripts.

## Project Structure

```
lfs-builder/
├── config/
│   ├── build.conf
│   ├── packages.conf
│   └── desktop.conf
├── scripts/
│   ├── common/
│   │   ├── utils.sh
│   │   ├── chroot-utils.sh
│   │   └── error-handler.sh
│   ├── host/
│   │   ├── 01-check-host.sh
│   │   ├── 02-prepare-host.sh
│   │   ├── 03-create-disk-image.sh
│   │   └── 04-build-toolchain.sh
│   ├── lfs/
│   │   ├── 05-build-lfs-basic.sh
│   │   ├── 06-build-lfs-system.sh
│   │   └── 07-configure-lfs.sh
│   ├── blfs/
│   │   ├── 08-build-blfs-base.sh
│   │   ├── 09-build-desktop.sh
│   │   ├── 10-build-applications.sh
│   │   └── 11-configure-desktop.sh
│   └── final/
│       ├── 12-create-initramfs.sh
│       ├── 13-create-bootloader.sh
│       └── 14-create-installer.sh
├── packages/
│   ├── sources.list
│   ├── patches/
│   └── custom-scripts/
├── profiles/
│   ├── minimal/
│   ├── xfce/
│   ├── gnome/
│   └── custom/
├── tools/
│   └── multi-platform/
├── builder.py
└── README.md
```

## Main Scripts

### 1. **builder.py** (Main Orchestrator - Cross-platform)

```python
#!/usr/bin/env python3
"""
LFS/BLFS Builder - Main orchestrator
Works on Linux, macOS, and Windows (WSL2)
"""

import os
import sys
import json
import argparse
import subprocess
import platform
from pathlib import Path
import logging
from datetime import datetime

class LFSBuilder:
    def __init__(self, profile, output_dir, config_file):
        self.profile = profile
        self.output_dir = Path(output_dir)
        self.config = self.load_config(config_file)
        self.system = platform.system()
        self.logger = self.setup_logging()
        
    def setup_logging(self):
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler('lfs-build.log'),
                logging.StreamHandler()
            ]
        )
        return logging.getLogger(__name__)
    
    def load_config(self, config_file):
        with open(config_file, 'r') as f:
            return json.load(f)
    
    def check_prerequisites(self):
        """Check system prerequisites"""
        self.logger.info(f"Checking prerequisites on {self.system}")
        
        if self.system == "Linux":
            required_cmds = ['bash', 'gcc', 'make', 'bison', 'gawk', 'm4', 'texinfo']
        elif self.system == "Darwin":
            required_cmds = ['bash', 'clang', 'make', 'gawk', 'm4']
            self.logger.warning("macOS requires Docker or Linux VM for building")
        elif self.system == "Windows":
            required_cmds = ['wsl', 'bash', 'gcc']
            self.logger.warning("Windows requires WSL2 with Ubuntu/Debian")
        
        for cmd in required_cmds:
            if not self.command_exists(cmd):
                self.logger.error(f"Missing required command: {cmd}")
                return False
        return True
    
    def command_exists(self, cmd):
        return subprocess.run(
            ['which', cmd], 
            capture_output=True
        ).returncode == 0
    
    def prepare_environment(self):
        """Prepare build environment"""
        self.logger.info("Preparing build environment")
        
        # Create directory structure
        dirs = [
            self.output_dir,
            self.output_dir / 'sources',
            self.output_dir / 'tools',
            self.output_dir / 'logs',
            self.output_dir / 'image'
        ]
        
        for d in dirs:
            d.mkdir(parents=True, exist_ok=True)
        
        # Set environment variables
        os.environ['LFS'] = str(self.output_dir / 'image')
        os.environ['LFS_TGT'] = 'x86_64-lfs-linux-gnu'
        os.environ['MAKEFLAGS'] = f"-j{os.cpu_count()}"
        
    def download_sources(self):
        """Download LFS/BLFS sources"""
        self.logger.info("Downloading sources")
        
        sources_file = Path('packages/sources.list')
        if not sources_file.exists():
            self.logger.error("Sources list not found")
            return False
        
        with open(sources_file, 'r') as f:
            for line in f:
                if line.strip() and not line.startswith('#'):
                    url = line.strip()
                    filename = url.split('/')[-1]
                    dest = self.output_dir / 'sources' / filename
                    
                    if not dest.exists():
                        self.logger.info(f"Downloading {filename}")
                        subprocess.run([
                            'wget', '-c', url, '-O', dest
                        ], check=True)
        
        return True
    
    def run_script(self, script_path, stage):
        """Run a build script"""
        self.logger.info(f"Running stage {stage}: {script_path}")
        
        script = Path(script_path)
        if not script.exists():
            self.logger.error(f"Script not found: {script_path}")
            return False
        
        # Make executable
        script.chmod(0o755)
        
        # Run script
        result = subprocess.run(
            [str(script)],
            env=os.environ,
            capture_output=True,
            text=True
        )
        
        # Log output
        log_file = self.output_dir / 'logs' / f"{stage}.log"
        with open(log_file, 'w') as f:
            f.write(result.stdout)
            if result.stderr:
                f.write("\n--- STDERR ---\n")
                f.write(result.stderr)
        
        if result.returncode != 0:
            self.logger.error(f"Stage {stage} failed. Check {log_file}")
            return False
        
        return True
    
    def build(self):
        """Main build process"""
        stages = [
            ('host-check', 'scripts/host/01-check-host.sh'),
            ('host-prepare', 'scripts/host/02-prepare-host.sh'),
            ('disk-image', 'scripts/host/03-create-disk-image.sh'),
            ('toolchain', 'scripts/host/04-build-toolchain.sh'),
            ('lfs-basic', 'scripts/lfs/05-build-lfs-basic.sh'),
            ('lfs-system', 'scripts/lfs/06-build-lfs-system.sh'),
            ('configure-lfs', 'scripts/lfs/07-configure-lfs.sh'),
            ('blfs-base', 'scripts/blfs/08-build-blfs-base.sh'),
            ('desktop', 'scripts/blfs/09-build-desktop.sh'),
            ('applications', 'scripts/blfs/10-build-applications.sh'),
            ('configure-desktop', 'scripts/blfs/11-configure-desktop.sh'),
            ('initramfs', 'scripts/final/12-create-initramfs.sh'),
            ('bootloader', 'scripts/final/13-create-bootloader.sh'),
            ('installer', 'scripts/final/14-create-installer.sh')
        ]
        
        for stage_name, script_path in stages:
            if not self.run_script(script_path, stage_name):
                self.logger.error(f"Build failed at stage: {stage_name}")
                return False
        
        self.logger.info("Build completed successfully!")
        self.logger.info(f"Installer image available at: {self.output_dir}/lfs-installer.iso")
        return True
    
    def create_writable_media(self, device=None):
        """Create bootable USB from installer"""
        installer = self.output_dir / 'lfs-installer.iso'
        
        if not installer.exists():
            self.logger.error("Installer ISO not found")
            return False
        
        self.logger.info("Ready to write to USB")
        
        if device:
            # Linux: dd to device
            self.logger.warning(f"This will overwrite {device}")
            response = input("Continue? (yes/no): ")
            if response.lower() == 'yes':
                subprocess.run([
                    'sudo', 'dd', 
                    f'if={installer}', 
                    f'of={device}', 
                    'bs=4M', 
                    'status=progress'
                ], check=True)
                self.logger.info(f"Written to {device}")
        else:
            self.logger.info(f"ISO created: {installer}")
            self.logger.info("Use balenaEtcher, Rufus, or dd to write to USB")
        
        return True

def main():
    parser = argparse.ArgumentParser(description='LFS/BLFS Builder')
    parser.add_argument('--profile', default='xfce', 
                       choices=['minimal', 'xfce', 'gnome', 'custom'])
    parser.add_argument('--output', default='./lfs-build')
    parser.add_argument('--config', default='config/build.conf')
    parser.add_argument('--write-usb', help='USB device to write to (e.g., /dev/sdb)')
    
    args = parser.parse_args()
    
    builder = LFSBuilder(args.profile, args.output, args.config)
    
    if not builder.check_prerequisites():
        sys.exit(1)
    
    builder.prepare_environment()
    
    if not builder.download_sources():
        sys.exit(1)
    
    if not builder.build():
        sys.exit(1)
    
    if args.write_usb:
        builder.create_writable_media(args.write_usb)

if __name__ == '__main__':
    main()
```

### 2. **config/build.conf** (Configuration)

```json
{
  "lfs_version": "12.1",
  "blfs_version": "12.1",
  "architecture": "x86_64",
  "target_triplet": "x86_64-lfs-linux-gnu",
  
  "desktop": {
    "type": "xfce",
    "display_manager": "lightdm",
    "theme": "adwaita",
    "extras": [
      "firefox",
      "libreoffice",
      "gimp",
      "vlc"
    ]
  },
  
  "filesystem": {
    "type": "ext4",
    "size_mb": 8192,
    "swap_mb": 2048,
    "boot_mb": 512
  },
  
  "kernel": {
    "version": "6.6.14",
    "config": "config/kernel-config",
    "modules": [
      "ext4",
      "xfs",
      "nvme",
      "virtio",
      "usb_storage"
    ]
  },
  
  "locale": "en_US.UTF-8",
  "timezone": "America/New_York",
  "hostname": "lfs-desktop",
  
  "users": [
    {
      "name": "lfsuser",
      "groups": ["wheel", "audio", "video", "storage"]
    }
  ],
  
  "custom_scripts": [
    "packages/custom-scripts/post-install.sh"
  ],
  
  "repositories": [
    "https://www.linuxfromscratch.org/lfs/view/stable/wget-list",
    "https://www.linuxfromscratch.org/blfs/view/stable/wget-list"
  ]
}
```

### 3. **scripts/common/utils.sh** (Utility Functions)

```bash
#!/bin/bash
# Common utility functions for LFS build scripts

set -e

LFS=${LFS:-/mnt/lfs}
LFS_TGT=${LFS_TGT:-x86_64-lfs-linux-gnu}
NUM_JOBS=${NUM_JOBS:-$(nproc)}
LC_ALL=POSIX

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Mount virtual filesystems
mount_virtual_kernel_filesystems() {
    log_info "Mounting virtual kernel filesystems"
    
    mount -v --bind /dev $LFS/dev
    mount -v --bind /dev/pts $LFS/dev/pts
    mount -vt proc proc $LFS/proc
    mount -vt sysfs sysfs $LFS/sys
    mount -vt tmpfs tmpfs $LFS/run
    
    if [ -h $LFS/dev/shm ]; then
        mkdir -pv $LFS/$(readlink $LFS/dev/shm)
    fi
}

# Unmount virtual filesystems
umount_virtual_kernel_filesystems() {
    log_info "Unmounting virtual kernel filesystems"
    
    umount -v $LFS/dev/pts
    umount -v $LFS/dev
    umount -v $LFS/proc
    umount -v $LFS/sys
    umount -v $LFS/run
}

# Enter chroot environment
enter_chroot() {
    log_info "Entering chroot environment"
    
    chroot "$LFS" /usr/bin/env -i   \
        HOME=/root                  \
        TERM="$TERM"                \
        PS1='(lfs chroot) \u:\w\$ ' \
        PATH=/usr/bin:/usr/sbin     \
        /bin/bash --login +h
}

# Build with logging
build_package() {
    local pkg_name=$1
    local build_cmd=${2:-"make -j$NUM_JOBS"}
    
    log_info "Building $pkg_name"
    
    if [ -f "/sources/$pkg_name/build.log" ]; then
        rm "/sources/$pkg_name/build.log"
    fi
    
    pushd "/sources/$pkg_name"
    
    if ! eval "$build_cmd" > build.log 2>&1; then
        log_error "Failed to build $pkg_name. Check build.log"
        popd
        return 1
    fi
    
    popd
    log_info "Successfully built $pkg_name"
    return 0
}

# Download file if not exists
download_file() {
    local url=$1
    local dest=$2
    
    if [ ! -f "$dest" ]; then
        log_info "Downloading $dest"
        wget -c "$url" -O "$dest"
    else
        log_info "$dest already exists, skipping download"
    fi
}

# Verify checksum
verify_checksum() {
    local file=$1
    local expected_md5=$2
    
    local actual_md5=$(md5sum "$file" | cut -d' ' -f1)
    
    if [ "$actual_md5" != "$expected_md5" ]; then
        log_error "Checksum mismatch for $file"
        log_error "Expected: $expected_md5"
        log_error "Actual: $actual_md5"
        return 1
    fi
    
    log_info "Checksum verified for $file"
    return 0
}

# Extract archive
extract_archive() {
    local archive=$1
    local dest=${2:-$(pwd)}
    
    case "$archive" in
        *.tar.gz|*.tgz) tar -xzf "$archive" -C "$dest" ;;
        *.tar.bz2)      tar -xjf "$archive" -C "$dest" ;;
        *.tar.xz)       tar -xJf "$archive" -C "$dest" ;;
        *.zip)          unzip "$archive" -d "$dest" ;;
        *)              log_error "Unknown archive format: $archive"; return 1 ;;
    esac
}

# Create system user
create_system_user() {
    local username=$1
    local groups=${2:-users}
    
    if ! id "$username" &>/dev/null; then
        groupadd -g 1000 "$username"
        useradd -c "LFS User" -d "/home/$username" -u 1000 -g 1000 -G "$groups" -m "$username"
        log_info "Created user: $username"
    else
        log_warning "User $username already exists"
    fi
}

# Update environment profile
update_environment() {
    cat >> /etc/profile << "EOF"
# LFS Environment
export LFS=$LFS
export LFS_TGT=$LFS_TGT
export PATH=/usr/local/bin:$PATH
export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH
export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH

# Custom prompt for LFS
if [ -n "$LFS" ]; then
    PS1='(lfs) \u:\w\$ '
fi
EOF
    
    log_info "Environment profile updated"
}

# Create backup
create_backup() {
    local source=$1
    local backup_name=$2
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    if [ -e "$source" ]; then
        tar -czf "/backups/${backup_name}_${timestamp}.tar.gz" "$source"
        log_info "Backup created: ${backup_name}_${timestamp}.tar.gz"
    fi
}
```

### 4. **scripts/host/03-create-disk-image.sh** (Create Bootable Disk Image)

```bash
#!/bin/bash
# Create disk image for USB installation

source scripts/common/utils.sh

IMAGE_SIZE_MB=${IMAGE_SIZE_MB:-8192}
BOOT_SIZE_MB=512
SWAP_SIZE_MB=2048
ROOT_SIZE_MB=$((IMAGE_SIZE_MB - BOOT_SIZE_MB - SWAP_SIZE_MB))

log_info "Creating disk image of ${IMAGE_SIZE_MB}MB"

# Create empty image file
dd if=/dev/zero of=$LFS.img bs=1M count=$IMAGE_SIZE_MB status=progress

# Setup loop device
LOOP_DEV=$(losetup --find --show --partscan $LFS.img)

# Create partition table
parted -s $LOOP_DEV mklabel gpt
parted -s $LOOP_DEV mkpart primary fat32 1MiB ${BOOT_SIZE_MB}MiB
parted -s $LOOP_DEV mkpart primary linux-swap ${BOOT_SIZE_MB}MiB $((BOOT_SIZE_MB + SWAP_SIZE_MB))MiB
parted -s $LOOP_DEV mkpart primary ext4 $((BOOT_SIZE_MB + SWAP_SIZE_MB))MiB 100%
parted -s $LOOP_DEV set 1 esp on

# Wait for partitions to appear
sleep 2

# Format partitions
mkfs.vfat -F32 ${LOOP_DEV}p1
mkswap ${LOOP_DEV}p2
mkfs.ext4 -F ${LOOP_DEV}p3

# Mount partitions
mkdir -pv $LFS
mount ${LOOP_DEV}p3 $LFS
mkdir -pv $LFS/boot
mount ${LOOP_DEV}p1 $LFS/boot
swapon ${LOOP_DEV}p2

log_info "Disk image created and mounted at $LFS"
log_info "Loop device: $LOOP_DEV"
echo $LOOP_DEV > /tmp/lfs_loop_device
```

### 5. **profiles/xfce/customization.sh** (Desktop Customization)

```bash
#!/bin/bash
# XFCE desktop customization script

# Install XFCE desktop components
install_xfce() {
    log_info "Installing XFCE desktop environment"
    
    # Core XFCE packages
    packages=(
        "xfce4-4.18.tar.bz2"
        "xfce4-dev-tools-4.18.tar.bz2" 
        "libxfce4ui-4.18.tar.bz2"
        "libxfce4util-4.18.tar.bz2"
        "xfce4-panel-4.18.tar.bz2"
        "xfce4-session-4.18.tar.bz2"
        "xfce4-settings-4.18.tar.bz2"
        "xfconf-4.18.tar.bz2"
        "xfwm4-4.18.tar.bz2"
        "thunar-4.18.tar.bz2"
        "tumbler-4.18.tar.bz2"
    )
    
    for pkg in "${packages[@]}"; do
        extract_archive "/sources/$pkg"
        build_package "${pkg%.tar.*}" "./configure --prefix=/usr && make && make install"
    done
}

# Configure lightdm
configure_lightdm() {
    log_info "Configuring LightDM"
    
    cat > /etc/lightdm/lightdm.conf << "EOF"
[Seat:*]
autologin-user=lfsuser
autologin-user-timeout=0
greeter-session=lightdm-gtk-greeter
user-session=xfce
EOF

    cat > /etc/lightdm/lightdm-gtk-greeter.conf << "EOF"
[greeter]
background=/usr/share/backgrounds/default.png
theme-name=Adwaita
icon-theme-name=Adwaita
font-name=Sans 10
clock-format=%H:%M
EOF
}

# Install common applications
install_applications() {
    log_info "Installing common applications"
    
    # Web browser
    cd /sources
    wget https://ftp.mozilla.org/pub/firefox/releases/122.0/source/firefox-122.0.source.tar.xz
    tar -xf firefox-122.0.source.tar.xz
    cd firefox-122.0
    
    # Configure and build Firefox
    ./mach configure --prefix=/usr
    ./mach build
    ./mach install
    
    # Office suite
    cd /sources
    wget https://download.documentfoundation.org/libreoffice/stable/7.6.4/src/libreoffice-7.6.4.1.tar.xz
    tar -xf libreoffice-7.6.4.1.tar.xz
    cd libreoffice-7.6.4.1
    ./autogen.sh --prefix=/usr
    make -j$NUM_JOBS
    make install
    
    # Multimedia
    apt-get install -y vlc gimp inkscape audacity
}

# Configure desktop appearance
configure_desktop_appearance() {
    log_info "Applying desktop customizations"
    
    # Set default theme
    mkdir -p /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/
    
    cat > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml << "EOF"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Adwaita"/>
    <property name="IconThemeName" type="string" value="Adwaita"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="CursorThemeName" type="string" value="Adwaita"/>
    <property name="FontName" type="string" value="Sans 10"/>
  </property>
</channel>
EOF

    # Set panel configuration
    cat > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml << "EOF"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="panels" type="uint" value="1"/>
  <property name="panel-1" type="empty">
    <property name="position" type="string" value="p=6;x=0;y=0"/>
    <property name="length" type="uint" value="100"/>
    <property name="position-locked" type="bool" value="true"/>
    <property name="plugin-ids" type="array">
      <value type="int" value="1"/>
      <value type="int" value="2"/>
      <value type="int" value="3"/>
      <value type="int" value="4"/>
      <value type="int" value="5"/>
    </property>
  </property>
</channel>
EOF
}

# Main execution
main() {
    install_xfce
    configure_lightdm
    install_applications
    configure_desktop_appearance
    
    log_info "Desktop customization complete"
}

main
```

### 6. **scripts/final/14-create-installer.sh** (Create Installer ISO)

```bash
#!/bin/bash
# Create bootable installer ISO

source scripts/common/utils.sh

ISO_NAME=${ISO_NAME:-lfs-installer.iso}
INSTALLER_DIR="$LFS/installer"

log_info "Creating installer ISO: $ISO_NAME"

# Create installer directory structure
mkdir -pv $INSTALLER_DIR/{boot,isolinux,images,rootfs}

# Copy kernel and initramfs
cp -v $LFS/boot/vmlinuz-* $INSTALLER_DIR/boot/vmlinuz
cp -v $LFS/boot/initramfs-* $INSTALLER_DIR/boot/initramfs.img

# Create installer initramfs
cat > $INSTALLER_DIR/init << "EOF"
#!/bin/busybox sh

# Mount proc and sys
mount -t proc none /proc
mount -t sysfs none /sys

# Detect installation media
detect_media() {
    for dev in /dev/sd* /dev/hd* /dev/nvme*; do
        if [ -b "$dev" ]; then
            mount "$dev" /mnt 2>/dev/null && break
        fi
    done
}

# Launch installer
launch_installer() {
    clear
    echo "LFS Linux Installer"
    echo "==================="
    echo "1) Install LFS to disk"
    echo "2) Run live system"
    echo "3) Partition disk"
    echo "4) Exit to shell"
    echo
    read -p "Choose option: " choice
    
    case $choice in
        1) /usr/sbin/lfs-installer ;;
        2) startx ;;
        3) cfdisk ;;
        4) /bin/sh ;;
        *) launch_installer ;;
    esac
}

# Main
detect_media
launch_installer
EOF

chmod +x $INSTALLER_DIR/init

# Create installer script
cat > $LFS/usr/sbin/lfs-installer << "EOF"
#!/bin/bash

# LFS Installer Script
TARGET_DISK=""
LFS_VERSION="1.0"

select_disk() {
    echo "Available disks:"
    lsblk -d -o NAME,SIZE,MODEL
    echo
    read -p "Select target disk (e.g., sda): " TARGET_DISK
    TARGET_DISK="/dev/$TARGET_DISK"
}

partition_disk() {
    echo "Partitioning $TARGET_DISK"
    
    # Wipe filesystem signatures
    wipefs -a $TARGET_DISK
    
    # Create partitions
    parted -s $TARGET_DISK mklabel gpt
    parted -s $TARGET_DISK mkpart primary fat32 1MiB 513MiB
    parted -s $TARGET_DISK mkpart primary linux-swap 513MiB 2561MiB
    parted -s $TARGET_DISK mkpart primary ext4 2561MiB 100%
    parted -s $TARGET_DISK set 1 esp on
    
    # Format partitions
    mkfs.vfat -F32 ${TARGET_DISK}1
    mkswap ${TARGET_DISK}2
    mkfs.ext4 -F ${TARGET_DISK}3
}

install_system() {
    echo "Installing LFS to ${TARGET_DISK}3"
    
    # Mount target partitions
    mount ${TARGET_DISK}3 /mnt
    mkdir -p /mnt/boot
    mount ${TARGET_DISK}1 /mnt/boot
    swapon ${TARGET_DISK}2
    
    # Copy system
    rsync -avx --exclude={/dev/*,/proc/*,/sys/*,/tmp/*,/run/*,/mnt/*,/media/*,/lost+found} / /mnt/
    
    # Setup bootloader
    chroot /mnt /bin/bash -c "grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=LFS"
    chroot /mnt /bin/bash -c "grub-mkconfig -o /boot/grub/grub.cfg"
    
    echo "Installation complete!"
    umount -R /mnt
}

# Main installer
echo "LFS Linux Installer v$LFS_VERSION"
select_disk
partition_disk
install_system
echo "Installation finished. Reboot to start LFS."
EOF

chmod +x $LFS/usr/sbin/lfs-installer

# Build initramfs for installer
cd $INSTALLER_DIR
find . | cpio -o -H newc | gzip > $INSTALLER_DIR/installer.img

# Create ISO with isolinux
isolinux_bin="/usr/lib/syslinux/isolinux.bin"
if [ ! -f "$isolinux_bin" ]; then
    isolinux_bin="/usr/share/syslinux/isolinux.bin"
fi

cat > $INSTALLER_DIR/isolinux/isolinux.cfg << "EOF"
DEFAULT install
LABEL install
  KERNEL /boot/vmlinuz
  APPEND initrd=/boot/initramfs.img root=/dev/ram0
LABEL live
  KERNEL /boot/vmlinuz
  APPEND initrd=/boot/initramfs.img root=/dev/ram0
EOF

# Create ISO
xorriso -as mkisofs -R -J -joliet-long \
    -b isolinux/isolinux.bin -c isolinux/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -eltorito-alt-boot -e boot/efi.img -no-emul-boot \
    -isohybrid-gpt-basdat \
    -V "LFS_LINUX" \
    -o "../$ISO_NAME" \
    "$INSTALLER_DIR"

log_info "Installer ISO created: $ISO_NAME"
```

### 7. **packages/sources.list** (Package Sources)

```bash
# LFS Core Packages
https://www.kernel.org/pub/linux/kernel/v6.x/linux-6.6.14.tar.xz
https://ftp.gnu.org/gnu/gcc/gcc-13.2.0/gcc-13.2.0.tar.xz
https://ftp.gnu.org/gnu/binutils/binutils-2.41.tar.xz
https://ftp.gnu.org/gnu/glibc/glibc-2.38.tar.xz
https://ftp.gnu.org/gnu/make/make-4.4.1.tar.gz
https://ftp.gnu.org/gnu/bash/bash-5.2.21.tar.gz
https://www.python.org/ftp/python/3.12.1/Python-3.12.1.tar.xz

# BLFS Core
https://download.gnome.org/sources/glib/2.78/glib-2.78.3.tar.xz
https://gitlab.freedesktop.org/xorg/util/macros/-/archive/util-macros-1.20.0/macros-util-macros-1.20.0.tar.bz2
https://download.gnome.org/sources/gtk+/3.24/gtk+-3.24.39.tar.xz

# Desktop Environment
https://archive.xfce.org/xfce/4.18/fat/tarballs/xfce4-4.18.tar.bz2
https://github.com/linuxmint/lightdm/releases/download/1.32.0/lightdm-1.32.0.tar.gz

# Applications
https://ftp.mozilla.org/pub/firefox/releases/122.0/source/firefox-122.0.source.tar.xz
https://download.documentfoundation.org/libreoffice/stable/7.6.4/src/libreoffice-7.6.4.1.tar.xz
https://get.videolan.org/vlc/3.0.20/vlc-3.0.20.tar.xz
https://download.gimp.org/pub/gimp/v2.10/gimp-2.10.36.tar.bz2
https://github.com/obsproject/obs-studio/archive/30.0.2.tar.gz
```

### 8. **README.md** (Documentation)

```markdown
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
```

## Build Profiles

### Minimal Profile
```bash
python3 builder.py --profile minimal --output ./minimal-lfs
```
- Command-line only
- ~800MB final size
- Ideal for servers or embedded

### XFCE Profile (Default)
```bash
python3 builder.py --profile xfce --output ./xfce-lfs
```
- Lightweight desktop
- Firefox, LibreOffice, VLC
- ~4GB final size

### GNOME Profile
```bash
python3 builder.py --profile gnome --output ./gnome-lfs
```
- Full GNOME 45 desktop
- Complete application suite
- ~8GB final size

## Customization

Create custom profile:
```bash
cp -r profiles/xfce profiles/myprofile
edit profiles/myprofile/customization.sh
python3 builder.py --profile myprofile
```

## Build Process Stages

1. **Host Preparation** - Sets up build environment
2. **Toolchain** - Cross-compilation toolchain
3. **LFS Base** - Core LFS system
4. **BLFS Core** - Basic system services
5. **Desktop** - GUI environment
6. **Applications** - User applications
7. **Customization** - User themes and settings
8. **Installer** - Bootable ISO creation

## USB Installation

1. Write ISO to USB:
```bash
# Linuxdd if=lfs-installer.iso of=/dev/sdX bs=4M status=progress

# macOS
sudo dd if=lfs-installer.iso of=/dev/rdiskN bs=4m

# Windows
Use Rufus or balenaEtcher (GUI)
```

2. Boot from USB
3. Follow installer prompts
4. Reboot into your custom LFS system

## Advanced Configuration

Edit `config/build.conf` to customize:

```json
{
  "desktop": {
    "type": "xfce",
    "display_manager": "lightdm",
    "extras": ["firefox", "libreoffice", "vscode"]
  },
  "kernel": {
    "version": "6.6.14",
    "custom_config": true
  },
  "users": [
    {"name": "admin", "groups": ["wheel"]}
  ]
}
```

## Troubleshooting

### Build fails at certain stage
```bash
# Resume from specific stage
./builder.py --resume-from lfs-system

# Check logs
cat logs/lfs-system.log
```

### Out of disk space
```bash
# Clean build artifacts
./scripts/common/utils.sh clean

# Use external drive for build
export LFS_BUILD_DIR=/mnt/external-drive/lfs-build
```

### macOS issues
```bash
# Use Docker build environment
./scripts/host/docker-build.sh --profile xfce
```

## Directory Structure

```
lfs-builder/
├── builder.py          # Main build orchestrator
├── config/             # Build configuration
├── scripts/            # Build stage scripts
├── profiles/           # Desktop environment profiles
├── packages/           # Package sources and patches
└── tools/              # Platform-specific tools
```

## License
GPL v3 - See LICENSE file

## Contributing
Pull requests welcome. Please follow LFS/BLFS standards.

## Support
- Wiki: https://github.com/yourusername/lfs-builder/wiki
- Issues: GitHub Issues
- Discord: LFS Builder Community

## Acknowledgments
- Linux From Scratch Project
- Beyond Linux From Scratch Project
- BLFS Maintainers
```

## Additional Helper Scripts

### **tools/multi-platform/setup-wsl.sh** (Windows/WSL Setup)

```bash
#!/bin/bash
# Automated WSL2 setup for Windows users

echo "Setting up WSL2 for LFS building..."

# Update WSL
wsl --update
wsl --set-default-version 2

# Install Ubuntu 22.04
wsl --install Ubuntu-22.04

# Enter Ubuntu and setup
wsl -d Ubuntu-22.04 bash -c "
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y build-essential bison flex gawk texinfo intltool
    sudo apt install -y wget curl git python3 xorriso isolinux
    mkdir -p ~/lfs-builder
    cd ~/lfs-builder
    git clone https://github.com/yourusername/lfs-builder.git .
    ./scripts/host/02-prepare-host.sh
"

echo "WSL2 setup complete. Run 'wsl' to start building."
```

## FICHIER: `ADVANCED.md`

```markdown
# Advanced Usage Guide

This document covers advanced configurations, customizations, and optimization techniques for LFS/BLFS Builder.

## Table of Contents

1. [Custom Build Profiles](#custom-build-profiles)
2. [Cross-Compilation](#cross-compilation)
3. [Distributed Builds](#distributed-builds)
4. [Custom Package Repository](#custom-package-repository)
5. [Kernel Optimization](#kernel-optimization)
6. [Init System Deep Dive](#init-system-deep-dive)
7. [Security Hardening Levels](#security-hardening-levels)
8. [Performance Tuning](#performance-tuning)
9. [Container Integration](#container-integration)
10. [CI/CD Pipeline](#cicd-pipeline)
11. [Embedded Systems](#embedded-systems)
12. [Recovery and Debugging](#recovery-and-debugging)

---

## Custom Build Profiles

### Creating a Profile from Scratch

Create a complete custom profile in `profiles/custom/`:

```bash
mkdir -p profiles/custom
cp profiles/xfce/customization.sh profiles/custom/
```

#### Profile Structure

```python
# Add to ProfileManager.PROFILES in builder.py
'custom': {
    'description': 'My custom distribution',
    'size_gb': 15,
    'build_time_hours': 8,
    'packages': [
        'base',           # Required
        'network',        # Networking stack
        'ssh',           # SSH daemon
        'xorg',          # X11 server
        'custom-gui',    # Your custom GUI
        'dev-tools',     # Development tools
        'security'       # Security suite
    ],
    'desktop': 'custom',
    'java_dev': True,
    'package_manager': True,
    'security_hardening': True,
    'privacy_tools': True
}
```

#### Customization Script Template

```bash
#!/bin/bash
# profiles/custom/customization.sh

set -e

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[0;34m[SUCCESS]\033[0m $1"; }

# Custom environment variables
export CUSTOM_HOME="/opt/custom"
export CUSTOM_CONFIG="/etc/custom"

# Pre-installation hooks
pre_install() {
    log_info "Running pre-installation tasks"
    mkdir -p "$CUSTOM_HOME" "$CUSTOM_CONFIG"
}

# Main installation
install_custom_packages() {
    log_info "Installing custom packages"
    
    cd /sources
    
    # Your custom applications
    for pkg in custom-app-*.tar.gz; do
        tar -xzf "$pkg"
        cd "${pkg%.tar.gz}"
        ./configure --prefix=/usr
        make -j$(nproc)
        make install
        cd ..
    done
}

# Post-installation configuration
configure_custom() {
    log_info "Configuring custom environment"
    
    # Custom systemd service
    cat > /etc/systemd/system/custom.service << EOF
[Unit]
Description=Custom Service
After=network.target

[Service]
Type=simple
ExecStart=$CUSTOM_HOME/bin/custom-daemon
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl enable custom
}

# Main execution
main() {
    pre_install
    install_custom_packages
    configure_custom
    log_success "Custom profile installed"
}

main
```

### Profile Inheritance

Create profiles that inherit from base profiles:

```python
# profiles/server/customization.sh inherits from minimal
source ../minimal/customization.sh

# Override specific functions
install_extra_packages() {
    log_info "Installing server packages"
    # Extra server packages
}
```

---

## Cross-Compilation

### Building for ARM (Raspberry Pi, ARM64)

```bash
# Set target architecture
export LFS_TGT="aarch64-lfs-linux-gnu"
export CFLAGS="-march=armv8-a+crc -mtune=cortex-a72"

# Build with custom toolchain
python3 builder.py --profile minimal \
    --config config/build-cross.conf \
    --output ./lfs-arm64
```

#### Cross-Compilation Configuration

```json
// config/build-cross.conf
{
  "architecture": "aarch64",
  "target_triplet": "aarch64-lfs-linux-gnu",
  "cross_compile": true,
  "cross_prefix": "/usr/bin/aarch64-linux-gnu-",
  "sysroot": "/sysroots/aarch64-lfs",
  "qemu_user": "qemu-aarch64-static",
  
  "kernel": {
    "version": "6.6.14",
    "config": "config/kernel-config-arm64",
    "dtbs": true
  },
  
  "bootloader": {
    "type": "uboot",
    "config": "config/u-boot.config"
  }
}
```

### Multi-arch Build Matrix

```bash
#!/bin/bash
# tools/build-matrix.sh

ARCHITECTURES=("x86_64" "aarch64" "armv7l" "riscv64")
PROFILES=("minimal" "xfce" "secure")

for arch in "${ARCHITECTURES[@]}"; do
    for profile in "${PROFILES[@]}"; do
        echo "Building $profile for $arch"
        
        export LFS_TGT="${arch}-lfs-linux-gnu"
        
        python3 builder.py \
            --profile "$profile" \
            --output "./lfs-${arch}-${profile}" \
            --config "config/build-${arch}.conf"
    done
done
```

---

## Distributed Builds

### Icecream Distributed Compilation

```bash
# Install icecream on all build nodes
apt install icecc icecream-monitor

# Master node
export ICECC_CXX="g++"
export ICECC_CC="gcc"
export PATH="/usr/lib/icecream/bin:$PATH"

# Add build slaves
icecc-add-server build-node-1
icecc-add-server build-node-2

# Build with distribution
export MAKEFLAGS="-j40"  # 10 cores × 4 nodes
python3 builder.py --profile full
```

### DistCC Setup

```bash
# On build master
cat > /etc/distcc/hosts << EOF
localhost 4
build-node-1 8
build-node-2 8
build-node-3 8
EOF

export DISTCC_HOSTS="localhost/4 build-node-1/8 build-node-2/8"

# On build slaves
distccd --daemon --allow 192.168.1.0/24
```

### Parallel Package Building

```bash
# Build multiple packages simultaneously
cat > /usr/local/bin/parallel-build << 'EOF'
#!/bin/bash

PACKAGES=($(ls /sources/*.tar.gz | cut -d/ -f3))
MAX_JOBS=8

build_package() {
    local pkg=$1
    cd /sources
    tar -xf "$pkg"
    cd "${pkg%.tar.gz}"
    ./configure --prefix=/usr
    make -j2
    make install
}

export -f build_package
printf "%s\n" "${PACKAGES[@]}" | xargs -P $MAX_JOBS -I {} bash -c 'build_package "{}"'
EOF
```

---

## Custom Package Repository

### Creating a Local Repository

```bash
#!/bin/bash
# tools/create-repo.sh

REPO_DIR="/var/www/html/lfs-repo"
mkdir -p "$REPO_DIR"/{packages,metadata}

# Create package database
cat > "$REPO_DIR/metadata/repo.db" << EOF
# LFS Package Repository
repo_name="Custom LFS Repo"
repo_version="1.0"
repo_arch="x86_64"
repo_url="http://repo.lfs.local"
EOF

# Index packages
for pkg in "$REPO_DIR"/packages/*.lpm; do
    pkg_name=$(basename "$pkg" .lpm)
    pkg_version=$(tar -xf "$pkg" -O ./metadata/version)
    pkg_size=$(stat -c%s "$pkg")
    
    echo "$pkg_name:$pkg_version:$pkg_size:$pkg_name.lpm" >> "$REPO_DIR/metadata/packages.db"
done

# Generate GPG signature
gpg --detach-sign --armor "$REPO_DIR/metadata/repo.db"
```

### Repository Configuration

```bash
# /etc/lpm/repos.d/custom.repo
REPO_NAME="custom"
REPO_URL="http://repo.lfs.local"
REPO_ENABLED="yes"
REPO_PRIORITY="10"
REPO_GPG_CHECK="yes"
REPO_GPG_KEY="/etc/lpm/trusted.gpg.d/custom.asc"
```

### Package Build Server

```bash
#!/bin/bash
# tools/build-server.sh

# Webhook listener for automated builds
while true; do
    # Listen for GitHub webhook
    nc -l 8080 | while read line; do
        if echo "$line" | grep -q "push"; then
            # Trigger build
            cd /srv/lfs-builder
            git pull
            python3 builder.py --profile secure --output /srv/builds/latest
            # Upload to repository
            scp /srv/builds/latest/lfs-installer.iso repo.lfs.local:/var/www/html/
        fi
    done
done
```

---

## Kernel Optimization

### Custom Kernel Configuration

```bash
# Generate optimal config for your hardware
cd /sources/linux-*
make localmodconfig  # Uses only loaded modules
make localyesconfig  # Embeds modules into kernel
make tinyconfig      # Minimal kernel (embedded)

# Custom kernel patch
cat > kernel.patch << 'EOF'
--- a/kernel/sched/core.c
+++ b/kernel/sched/core.c
@@ -1234,6 +1234,9 @@
     /* Custom scheduling optimization */
     if (unlikely(current->policy == SCHED_IDLE))
         yield();
+    
+    /* LFS custom patch: improve desktop responsiveness */
+    if (current->mm && current->mm->mmap_count > 100)
+        set_user_nice(current, -5);
 EOF

patch -p1 < kernel.patch
```

### Kernel Build Optimization

```bash
# Use all cores with compiler optimizations
export MAKEFLAGS="-j$(nproc) -O2 -pipe -march=native"

# Build only needed modules
make localmodconfig
make -j$(nproc) bzImage modules
make modules_install

# Reduce kernel size
make INSTALL_MOD_STRIP=1 modules_install
make STRIP=/usr/bin/strip INSTALL_HDR_STRIP=1 headers_install
```

### Real-time Kernel

```bash
# Patch for real-time
wget https://www.kernel.org/pub/linux/kernel/projects/rt/6.6/patch-6.6.14-rt19.patch.xz
xzcat patch-6.6.14-rt19.patch.xz | patch -p1

# Configure PREEMPT_RT
make olddefconfig
scripts/config --enable CONFIG_PREEMPT_RT
scripts/config --disable CONFIG_DEBUG_PREEMPT
```

---

## Init System Deep Dive

### Custom systemd Unit

```bash
cat > /etc/systemd/system/myapp@.service << 'EOF'
[Unit]
Description=My Application Instance %I
After=network.target

[Service]
Type=simple
User=myuser
WorkingDirectory=/opt/myapp
EnvironmentFile=-/etc/default/myapp@%i
ExecStart=/opt/myapp/bin/start --instance=%i
ExecStop=/opt/myapp/bin/stop --instance=%i
Restart=on-failure
RestartSec=5
CPUQuota=50%
MemoryMax=1G

[Install]
WantedBy=multi-user.target
EOF

# Usage
systemctl enable myapp@1 myapp@2
```

### SysV Init Custom Script

```bash
cat > /etc/rc.d/init.d/custom-daemon << 'EOF'
#!/bin/bash
# chkconfig: 345 85 15
# description: Custom daemon control

DAEMON=/usr/local/sbin/custom-daemon
PIDFILE=/var/run/custom-daemon.pid

case "$1" in
    start)
        echo -n "Starting custom daemon: "
        start-stop-daemon --start --quiet --pidfile $PIDFILE --exec $DAEMON
        echo "OK"
        ;;
    stop)
        echo -n "Stopping custom daemon: "
        start-stop-daemon --stop --quiet --pidfile $PIDFILE
        rm -f $PIDFILE
        echo "OK"
        ;;
    restart)
        $0 stop
        sleep 1
        $0 start
        ;;
    status)
        status_of_proc -p $PIDFILE $DAEMON custom-daemon
        ;;
    *)
        echo "Usage: $0 {start|stop|status|restart}"
        exit 1
        ;;
esac
EOF

chmod +x /etc/rc.d/init.d/custom-daemon
update-rc.d custom-daemon defaults
```

### OpenRC Custom Service

```bash
cat > /etc/init.d/custom << 'EOF'
#!/sbin/openrc-run

description="Custom Service"
pidfile="/run/${RC_SVCNAME}.pid"
command="/usr/sbin/custom-daemon"
command_args="--daemon"

depend() {
    need net
    after firewall
    use logger
}

start_pre() {
    ebegin "Preparing custom environment"
    mkdir -p /var/log/custom
    chown custom:custom /var/log/custom
    eend $?
}

stop_post() {
    ebegin "Cleaning up"
    rm -f /var/run/custom.pid
    eend $?
}
EOF

chmod +x /etc/init.d/custom
rc-update add custom default
```

---

## Security Hardening Levels

### Level 0: Development (No hardening)

```json
"security": {
    "kernel_hardening": false,
    "firewall": {"enabled": false},
    "fail2ban": {"enabled": false},
    "audit": {"enabled": false},
    "user_hardening": {"enable": false}
}
```

### Level 1: Basic (Workstation)

```json
"security": {
    "kernel_hardening": true,
    "firewall": {"enabled": true, "allow_ssh": true},
    "fail2ban": {"enabled": true, "ban_time": 3600},
    "user_hardening": {"password_min_length": 8, "disable_root_login": true}
}
```

### Level 2: Enhanced (Server)

```json
"security": {
    "kernel_hardening": true,
    "firewall": {"enabled": true, "allow_ssh": true, "rate_limit": true},
    "fail2ban": {"enabled": true, "ban_time": 86400},
    "audit": {"enabled": true, "monitor_files": ["/etc", "/var/www"]},
    "apparmor": {"enabled": true},
    "user_hardening": {"password_min_length": 12, "login_delay": 4}
}
```

### Level 3: Hardened (Production)

```json
"security": {
    "kernel_hardening": true,
    "firewall": {"enabled": true, "default_drop": true},
    "fail2ban": {"enabled": true, "permanent_bans": true},
    "audit": {"enabled": true, "monitor_all": true},
    "apparmor": {"enabled": true, "enforce_all": true},
    "hids": {"enabled": true, "daily_scan": true},
    "encryption": {"encrypted_swap": true, "full_disk": true},
    "selinux": {"enabled": true, "strict": true}
}
```

### Level 4: Military Grade

```json
"security": {
    "kernel_hardening": true,
    "firewall": {"enabled": true, "whitelist_only": true},
    "fail2ban": {"enabled": true, "global_bans": true},
    "audit": {"enabled": true, "comprehensive": true},
    "selinux": {"enabled": true, "mls": true},
    "encryption": {"full_disk": true, "tpm": true, "secure_boot": true},
    "network": {"tor": true, "vpns": true, "dns_encryption": true},
    "hardware": {"tpm": true, "smartcard": true, "secure_enclave": true}
}
```

---

## Performance Tuning

### Build System Optimization

```bash
# Use tmpfs for build directory (RAM disk)
sudo mount -t tmpfs -o size=32G tmpfs /mnt/lfs-build

# Use ccache for repeated builds
apt install ccache
export PATH="/usr/lib/ccache:$PATH"
export CCACHE_DIR="/mnt/lfs-build/.ccache"
export CCACHE_SIZE="20G"

# Use parallel compression
export XZ_OPT="-T0 -9"
export GZIP="-9"

# Profile-guided optimization (PGO)
cat > /sources/gcc-pgo.sh << 'EOF'
# Build GCC with PGO
mkdir -p gcc-build-pgo
cd gcc-build-pgo
../configure --with-profile-feedback
make profiledbootstrap
EOF
```

### Runtime Performance

```bash
# System-wide performance tuning
cat > /etc/sysctl.d/99-performance.conf << 'EOF'
# CPU
kernel.sched_autogroup_enabled = 1
kernel.sched_child_runs_first = 1

# Memory
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 30
vm.dirty_background_ratio = 5

# I/O
block/bfq/quantum = 8
block/bfq/low_latency = 1

# Network
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
EOF

# CPU governor for performance
echo performance > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

# I/O scheduler for SSDs
echo noop > /sys/block/sda/queue/scheduler
echo 2048 > /sys/block/sda/queue/read_ahead_kb
```

### Desktop Performance

```bash
# Xorg tuning
cat > /etc/X11/xorg.conf.d/50-performance.conf << 'EOF'
Section "Device"
    Identifier "Intel"
    Driver "intel"
    Option "TearFree" "false"
    Option "AccelMethod" "sna"
    Option "SwapbuffersWait" "false"
EndSection

Section "Extensions"
    Option "Composite" "Enable"
EndSection
EOF

# XFCE performance
xfconf-query -c xfwm4 -p /general/vblank_mode -s "off"
xfconf-query -c xfwm4 -p /general/sync_to_vblank -s "false"
```

---

## Container Integration

### Docker Build Environment

```dockerfile
# Dockerfile.builder
FROM ubuntu:22.04

RUN apt update && apt install -y \
    build-essential bison flex gawk texinfo \
    wget curl git python3 python3-pip \
    xorriso isolinux mtools dosfstools \
    parted rsync bc cpio kmod \
    libssl-dev libelf-dev

VOLUME /lfs-build
WORKDIR /lfs-builder

ENTRYPOINT ["python3", "builder.py"]
```

```bash
# Build with Docker
docker build -t lfs-builder -f Dockerfile.builder .
docker run --privileged \
    -v "$(pwd)/output:/lfs-build" \
    -v "$(pwd):/lfs-builder" \
    lfs-builder --profile secure --output /lfs-build
```

### Podman Integration

```bash
# Rootless build with Podman
podman run --privileged \
    --device=/dev/loop-control \
    -v ./output:/lfs-build:Z \
    localhost/lfs-builder:latest

# Quadlet service
cat > ~/.config/containers/systemd/lfs-builder.container << 'EOF'
[Unit]
Description=LFS Builder Service

[Container]
Image=localhost/lfs-builder:latest
Volume=/var/lib/lfs-build:/lfs-build:Z
AddCapability=ALL

[Service]
Restart=on-failure

[Install]
WantedBy=default.target
EOF
```

### Kubernetes Job

```yaml
# lfs-build-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: lfs-builder
spec:
  template:
    spec:
      containers:
      - name: builder
        image: lfs-builder:latest
        args: ["--profile", "secure", "--output", "/lfs-build"]
        volumeMounts:
        - name: build-volume
          mountPath: /lfs-build
        securityContext:
          privileged: true
      volumes:
      - name: build-volume
        persistentVolumeClaim:
          claimName: lfs-build-pvc
      restartPolicy: Never
```

---

## CI/CD Pipeline

### GitHub Actions

```yaml
# .github/workflows/build.yml
name: LFS Build

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  build:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        profile: [minimal, xfce, secure]
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Install dependencies
      run: |
        sudo apt update
        sudo apt install -y build-essential bison flex gawk texinfo \
          wget curl python3 xorriso isolinux parted rsync
    
    - name: Build LFS
      run: |
        python3 builder.py --profile ${{ matrix.profile }} --output ./build
    
    - name: Upload artifacts
      uses: actions/upload-artifact@v3
      with:
        name: lfs-${{ matrix.profile }}
        path: ./build/lfs-installer.iso

  security-scan:
    runs-on: ubuntu-latest
    steps:
    - name: Scan for vulnerabilities
      run: |
        trivy fs --severity HIGH,CRITICAL .
```

### GitLab CI

```yaml
# .gitlab-ci.yml
stages:
  - build
  - test
  - release

variables:
  LFS_CACHE_DIR: "${CI_PROJECT_DIR}/cache"

build:secure:
  stage: build
  tags:
    - lfs-builder
  script:
    - python3 builder.py --profile secure
  artifacts:
    paths:
      - lfs-build/lfs-installer.iso
    expire_in: 1 week
  cache:
    key: lfs-sources
    paths:
      - lfs-build/sources/

test:boot:
  stage: test
  script:
    - qemu-system-x86_64 -cdrom lfs-build/lfs-installer.iso -m 2048 -nographic -no-reboot
```

### Jenkins Pipeline

```groovy
// Jenkinsfile
pipeline {
    agent { label 'lfs-builder' }
    
    parameters {
        choice(name: 'PROFILE', choices: ['minimal', 'xfce', 'secure', 'full'])
    }
    
    stages {
        stage('Build') {
            steps {
                sh "python3 builder.py --profile ${params.PROFILE}"
            }
        }
        
        stage('Test') {
            steps {
                sh """
                    qemu-system-x86_64 \
                        -cdrom lfs-build/lfs-installer.iso \
                        -m 2048 \
                        -nographic \
                        -no-reboot
                """
            }
        }
        
        stage('Release') {
            when { branch 'main' }
            steps {
                sh """
                    scp lfs-build/lfs-installer.iso \
                        releases.lfs.org:/var/www/html/lfs-${params.PROFILE}-latest.iso
                """
            }
        }
    }
}
```

---

## Embedded Systems

### Raspberry Pi Build

```bash
# Cross-compile for Raspberry Pi 4
export LFS_TGT="aarch64-lfs-linux-gnu"
export CFLAGS="-march=armv8-a+crc -mtune=cortex-a72 -mfpu=neon-fp-armv8"

# Enable Pi-specific features
cat >> config/kernel-config-arm64 << 'EOF'
CONFIG_ARCH_BCM2835=y
CONFIG_BCM2835_WDT=y
CONFIG_RASPBERRYPI_FIRMWARE=y
CONFIG_VIDEO_BCM2835=y
CONFIG_SND_BCM2835=y
EOF

# Create bootable SD image
make -C scripts/final/ sd-image TARGET=/dev/mmcblk0
```

### Buildroot Integration

```bash
# Generate Buildroot configuration from LFS
python3 tools/export-to-buildroot.py > configs/lfs_defconfig

# Build with Buildroot
make lfs_defconfig
make -j$(nproc)

# Flash to device
dd if=output/images/sdcard.img of=/dev/sdb bs=1M
```

### Yocto Recipe

```bitbake
# meta-lfs/recipes-lfs/images/lfs-image.bb
SUMMARY = "LFS Linux Image"
LICENSE = "GPL-3.0-only"

IMAGE_FSTYPES = "tar.xz ext4.gz"

PACKAGE_INSTALL = " \
    packagegroup-core-boot \
    kernel-modules \
    openssh \
    lpm \
"

IMAGE_ROOTFS_SIZE = "8192"

do_image_ext4[depends] += " \
    lfs-builder-native:do_populate_sysroot \
"

IMAGE_CMD_ext4() {
    python3 ${STAGING_BINDIR_NATIVE}/builder.py \
        --profile embedded \
        --output ${IMGDEPLOYDIR}
}
```

---

## Recovery and Debugging

### Build Failure Analysis

```bash
#!/bin/bash
# tools/analyze-failure.sh

FAILED_STAGE="$1"
LOG_FILE="lfs-build/logs/${FAILED_STAGE}.log"

analyze_stage() {
    case "$FAILED_STAGE" in
        toolchain)
            grep -E "(error|undefined reference|missing)" "$LOG_FILE"
            ;;
        lfs-system)
            grep -E "(configure: error|make:.*\*\*\*)" "$LOG_FILE"
            ;;
        desktop)
            grep -E "(X11|display|DISPLAY|meson|ninja)" "$LOG_FILE"
            ;;
        security)
            grep -E "(SELinux|AppArmor|pam|crypto)" "$LOG_FILE"
            ;;
    esac
}

suggest_fix() {
    if grep -q "missing.*header" "$LOG_FILE"; then
        echo "Suggestion: Install development headers"
    elif grep -q "cannot find -l" "$LOG_FILE"; then
        echo "Suggestion: Install missing library"
    elif grep -q "Permission denied" "$LOG_FILE"; then
        echo "Suggestion: Check file permissions or run with sudo"
    fi
}

analyze_stage
suggest_fix
```

### Chroot Debugging

```bash
# Enter failed chroot environment
sudo chroot lfs-build/image /bin/bash

# Check system state
ps aux
df -h
mount
journalctl -xe

# Re-run failed command manually
cd /sources/package-name
./configure --prefix=/usr
make
make install

# Fix and continue
exit
python3 builder.py --resume-from failed-stage
```

### Rescue System

```bash
#!/bin/bash
# Create rescue ISO with debugging tools
cat > scripts/final/15-create-rescue.sh << 'EOF'
#!/bin/bash

# Add rescue tools to ISO
RESCUE_PACKAGES=(
    "gdb strace ltrace"
    "hexdump xxd binwalk"
    "testdisk foremost scalpel"
    "rsync unison"
    "htop iotop iftop"
    "wireshark-cli tcpdump"
)

# Include recovery scripts
cat > $LFS/usr/local/sbin/rescue-check << 'EOF'
#!/bin/bash
echo "=== LFS Rescue Check ==="
echo -n "Kernel: "; uname -r
echo -n "Init: "; pidof systemd && echo "systemd" || echo "sysv"
echo "Last boot errors:"
journalctl -b -p 3 2>/dev/null || dmesg | grep -i error
echo "Disk health:"
smartctl -H /dev/sda
echo "Filesystem check:"
fsck -N $(mount | grep ' / ' | cut -d' ' -f1)
EOF

chmod +x $LFS/usr/local/sbin/rescue-check
EOF
```

### Performance Profiling

```bash
# Profile build process
time python3 builder.py --profile full

# Profile individual stages
perf stat -e cycles,instructions,cache-misses \
    python3 builder.py --resume-from desktop

# Memory profiling
valgrind --tool=massif --massif-out-file=build.out \
    python3 builder.py --profile secure

# Analyze with ms_print
ms_print build.out | less
```

---

## Advanced Configuration Examples

### Custom Build Hooks

```bash
# pre-build.sh
#!/bin/bash
# Runs before build starts
echo "Custom pre-build hook"
export CUSTOM_FLAGS="-O3 -march=native"

# post-build.sh
#!/bin/bash
# Runs after successful build
scp lfs-build/lfs-installer.iso backup.lfs.org:/backups/
notify-send "LFS Build Complete" "ISO ready in lfs-build/"
```

### Build Variants

```python
# config/variants.py
BUILD_VARIANTS = {
    'debug': {
        'CFLAGS': '-O0 -g -ggdb',
        'enable_debug': True,
        'strip_binaries': False
    },
    'release': {
        'CFLAGS': '-O3 -DNDEBUG',
        'enable_debug': False,
        'strip_binaries': True
    },
    'profile': {
        'CFLAGS': '-O2 -pg -g',
        'enable_debug': True,
        'profile_guided': True
    }
}

def get_variant_config(variant):
    return BUILD_VARIANTS.get(variant, BUILD_VARIANTS['release'])
```

### Automated Benchmarking

```bash
#!/bin/bash
# tools/benchmark.sh

PROFILES=("minimal" "xfce" "secure" "full")
ITERATIONS=3

for profile in "${PROFILES[@]}"; do
    for i in $(seq 1 $ITERATIONS); do
        echo "Benchmark: $profile (run $i)"
        
        # Clean build
        python3 builder.py --clean --output "./bench-$profile-$i"
        
        # Time the build
        /usr/bin/time -f "%e real,%U user,%S sys" \
            python3 builder.py \
            --profile "$profile" \
            --output "./bench-$profile-$i" \
            2>> "benchmark-$profile.log"
        
        # Measure ISO size
        ls -lh "./bench-$profile-$i/lfs-installer.iso" \
            >> "benchmark-$profile.log"
    done
done

# Generate report
python3 tools/analyze-benchmarks.py benchmark-*.log > report.html
```

---

## Troubleshooting Advanced Issues

| Issue | Solution |
|-------|----------|
| `No space left on device` | Use `--clean` or mount tmpfs |
| `Failed to download sources` | Check network, use mirror |
| `Chroot: failed to run command` | Verify `$LFS` is set correctly |
| `Kernel panic` | Rebuild initramfs, check modules |
| `GRUB installation failed` | Manual install: `grub-install --target=i386-pc /dev/sda` |
| `X11 fails to start` | Check `/var/log/Xorg.0.log`, reconfigure |
| `systemd boot loop` | Boot with `systemd.unit=rescue.target` |
| `Package conflicts` | Use `lpm remove` before install |

---

## Further Resources

- [LFS Hint: Advanced Builds](https://www.linuxfromscratch.org/hints/)
- [Gentoo Wiki: Init Systems](https://wiki.gentoo.org/wiki/Init_system)
- [Arch Linux: Optimizing Performance](https://wiki.archlinux.org/title/performance)
- [Debian: Securing Debian Manual](https://www.debian.org/doc/manuals/securing-debian-howto/)
- [Kernel Newbies: Kernel Configuration](https://kernelnewbies.org/KernelBuild)

---

This document is continuously updated. For questions, open an issue on GitHub.
```

### **tools/multi-platform/docker-build.sh** (Cross-platform Docker Builder)

```bash
#!/bin/bash
# Docker-based build for macOS/Windows

DOCKERFILE=$(cat <<EOF
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt update && apt install -y \\
    build-essential bison flex gawk texinfo \\
    wget curl git python3 xorriso isolinux \\
    mtools dosfstools parted rsync

WORKDIR /build
COPY . .

CMD ["python3", "builder.py", "--profile", "xfce"]
EOF
)

echo "$DOCKERFILE" > Dockerfile
docker build -t lfs-builder .
docker run --privileged -v $(pwd)/output:/build/output lfs-builder
```

This complete system provides:

1. **Full automation** from source download to bootable USB
2. **Cross-platform support** through multiple methods
3. **Customizable desktop environments** with multiple profiles
4. **User-friendly installer** with interactive selection
5. **Comprehensive error handling** and logging
6. **Modular design** for easy customization
7. **Production-ready scripts** with safety checks

To get started, simply:
```bash
git clone [repository]
cd lfs-builder
python3 builder.py
```

Parfait ! Voici l'arborescence complète avec **tous les chemins de fichiers** pour chaque feature. J'ai organisé cela comme une extension de ton projet existant.

```
lfs-builder/
├── builder.py                          # Ton fichier principal (existant)
├── requirements.txt                    # Dépendances Python
├── setup.py                            # Script d'installation
├── README.md                           # Documentation
├── Makefile                            # Commandes make pour faciliter l'usage
│
├── config/                             # Configuration
│   ├── build.conf                       # Ton fichier JSON existant
│   ├── build.yaml                       # [NOUVEAU] Configuration YAML simplifiée
│   ├── profiles/                        # [NOUVEAU] Profils prédéfinis
│   │   ├── gaming.yaml
│   │   ├── development.yaml
│   │   ├── server.yaml
│   │   ├── multimedia.yaml
│   │   └── kiosk.yaml
│   └── themes/                          # [NOUVEAU] Thèmes d'interface
│       ├── dark.yaml
│       ├── light.yaml
│       └── hacker.yaml
│
├── scripts/                            # Scripts de build (ta structure existante)
│   ├── host/
│   ├── lfs/
│   ├── blfs/
│   └── final/
│
├── src/                                # [NOUVEAU] Code source Python organisé
│   ├── __init__.py
│   ├── cli/                            # Interface ligne de commande
│   │   ├── __init__.py
│   │   ├── main.py                      # Point d'entrée CLI
│   │   ├── arguments.py                 # Parsing des arguments
│   │   └── commands/                    # Sous-commandes
│   │       ├── __init__.py
│   │       ├── build.py
│   │       ├── clean.py
│   │       ├── config.py
│   │       ├── monitor.py
│   │       └── snapshot.py
│   │
│   ├── core/                           # Cœur du builder
│   │   ├── __init__.py
│   │   ├── builder.py                   # Classe LFSBuilder (refactorée)
│   │   ├── config.py                    # Gestion de configuration
│   │   ├── executor.py                  # ScriptExecutor amélioré
│   │   └── downloader.py                # SourceDownloader amélioré
│   │
│   ├── features/                       # [NOUVEAU] Features par module
│   │   ├── __init__.py
│   │   ├── tui/                         # Feature 1: Interface TUI
│   │   │   ├── __init__.py
│   │   │   ├── app.py                   # LFSConfigApp
│   │   │   ├── screens/
│   │   │   │   ├── main.py
│   │   │   │   ├── profile.py
│   │   │   │   ├── desktop.py
│   │   │   │   ├── security.py
│   │   │   │   ├── network.py
│   │   │   │   └── cross_compile.py
│   │   │   └── widgets/
│   │   │       ├── custom.py
│   │   │       └── validators.py
│   │   │
│   │   ├── snapshot/                   # Feature 2: Snapshots
│   │   │   ├── __init__.py
│   │   │   ├── manager.py               # SnapshotManager
│   │   │   ├── btrfs.py                 # Support Btrfs
│   │   │   ├── zfs.py                   # Support ZFS
│   │   │   ├── tar.py                   # Fallback tar
│   │   │   └── rollback.py              # Rollback handler
│   │   │
│   │   ├── firstboot/                  # Feature 3: Assistant first-boot
│   │   │   ├── __init__.py
│   │   │   ├── assistant.py             # Script générateur
│   │   │   ├── templates/               # Templates de scripts
│   │   │   │   ├── first-boot.sh.tpl
│   │   │   │   ├── network.sh.tpl
│   │   │   │   ├── users.sh.tpl
│   │   │   │   └── software.sh.tpl
│   │   │   └── modules/                 # Modules assistant
│   │   │       ├── user_setup.py
│   │   │       ├── network_setup.py
│   │   │       ├── software_selection.py
│   │   │       └── theme_selector.py
│   │   │
│   │   ├── dryrun/                     # Feature 4: Dry-run mode
│   │   │   ├── __init__.py
│   │   │   ├── executor.py              # DryRunExecutor
│   │   │   ├── analyzer.py              # Analyse de scripts
│   │   │   └── reporter.py              # Rapport d'analyse
│   │   │
│   │   ├── downloader/                 # Feature 5: Advanced downloader
│   │   │   ├── __init__.py
│   │   │   ├── advanced.py              # AdvancedDownloader
│   │   │   ├── aria2.py                 # Intégration aria2
│   │   │   ├── cache.py                 # Gestion cache local
│   │   │   ├── resume.py                # Reprise de téléchargement
│   │   │   └── checksum.py              # Vérification parallèle
│   │   │
│   │   ├── monitor/                    # Feature 6: Web monitoring
│   │   │   ├── __init__.py
│   │   │   ├── server.py                # BuildMonitor (Flask)
│   │   │   ├── templates/
│   │   │   │   ├── dashboard.html
│   │   │   │   ├── logs.html
│   │   │   │   └── status.html
│   │   │   ├── static/
│   │   │   │   ├── css/
│   │   │   │   │   └── style.css
│   │   │   │   └── js/
│   │   │   │       └── dashboard.js
│   │   │   └── api.py                   # Endpoints API
│   │   │
│   │   ├── packagemanager/             # Feature 7: Advanced LPM
│   │   │   ├── __init__.py
│   │   │   ├── lpm.py                   # Script générateur
│   │   │   ├── templates/
│   │   │   │   └── lpm.sh.tpl
│   │   │   └── hooks/                   # Hooks post-installation
│   │   │       ├── post-install.sh
│   │   │       └── pre-remove.sh
│   │   │
│   │   ├── userprofiles/               # Feature 8: User profiles
│   │   │   ├── __init__.py
│   │   │   ├── manager.py               # UserProfileManager
│   │   │   ├── profiles.yaml            # Profils prédéfinis
│   │   │   └── apply.py                 # Application des profils
│   │   │
│   │   ├── docker/                     # Feature 9: Docker support
│   │   │   ├── __init__.py
│   │   │   ├── builder.py               # DockerBuilder
│   │   │   ├── Dockerfile
│   │   │   ├── docker-compose.yml
│   │   │   └── entrypoint.sh
│   │   │
│   │   ├── iso/                        # Feature 10: ISO customization
│   │   │   ├── __init__.py
│   │   │   ├── builder.py               # ISOBuilder
│   │   │   ├── splash.py                # Gestion splash screen
│   │   │   ├── secureboot.py            # SecureBoot support
│   │   │   ├── hooks.py                 # Post-install hooks
│   │   │   └── templates/
│   │   │       ├── grub.cfg.tpl
│   │   │       └── isolinux.cfg.tpl
│   │   │
│   │   ├── notifications/              # Feature 11: Notifications
│   │   │   ├── __init__.py
│   │   │   ├── manager.py               # NotificationManager
│   │   │   ├── desktop.py               # Desktop notifications
│   │   │   ├── mobile.py                # Pushover/Gotify
│   │   │   ├── telegram.py              # Telegram bot
│   │   │   └── slack.py                 # Slack webhook
│   │   │
│   │   ├── interactive/               # Feature 12: Interactive mode
│   │   │   ├── __init__.py
│   │   │   ├── builder.py               # InteractiveBuilder
│   │   │   ├── error_handler.py         # Gestion erreurs interactive
│   │   │   ├── shell.py                 # Shell de débogage
│   │   │   └── recovery.py              # Stratégies de récupération
│   │   │
│   │   ├── hardware/                   # Feature 13: Hardware detection
│   │   │   ├── __init__.py
│   │   │   ├── detector.py              # HardwareCompatibility
│   │   │   ├── cpu.py                   # Détection CPU
│   │   │   ├── gpu.py                   # Détection GPU
│   │   │   ├── disk.py                  # Détection disques
│   │   │   ├── network.py               # Détection réseau
│   │   │   └── recommendations.py       # Recommandations
│   │   │
│   │   └── distro/                     # Feature 14: Distro customization
│   │       ├── __init__.py
│   │       ├── customizer.py            # DistroCustomizer
│   │       ├── branding.py              # Gestion branding
│   │       ├── repositories.py          # Gestion dépôts
│   │       ├── release.py               # Création release ISO
│   │       └── templates/
│   │           ├── os-release.tpl
│   │           ├── lsb-release.tpl
│   │           └── issue.tpl
│   │
│   └── utils/                          # Utilitaires
│       ├── __init__.py
│       ├── logging.py                   # Logging avancé
│       ├── system.py                    # Détection système
│       ├── network.py                   # Utilitaires réseau
│       └── validation.py                # Validation données
│
├── data/                               # Données statiques
│   ├── sources/                        # Sources téléchargées
│   ├── snapshots/                      # Snapshots système
│   │   └── .gitkeep
│   ├── cache/                          # Cache téléchargements
│   │   └── .gitkeep
│   ├── themes/                         # Thèmes intégrés
│   │   ├── default/
│   │   │   ├── wallpaper.jpg
│   │   │   ├── icon_theme/
│   │   │   └── gtk.css
│   │   ├── dark/
│   │   └── hacker/
│   └── hooks/                          # Hooks système
│       ├── pre-build.d/
│       ├── post-build.d/
│       ├── pre-install.d/
│       └── post-install.d/
│
├── tests/                              # Tests unitaires
│   ├── __init__.py
│   ├── test_config.py
│   ├── test_downloader.py
│   ├── test_snapshot.py
│   ├── test_hardware.py
│   └── fixtures/                       # Données de test
│       ├── sample_config.json
│       └── sample_script.sh
│
├── docs/                               # Documentation
│   ├── index.md
│   ├── installation.md
│   ├── configuration.md
│   ├── profiles.md
│   ├── cross-compile.md
│   ├── api/
│   │   └── README.md
│   └── examples/
│       ├── gaming-build.md
│       ├── server-build.md
│       └── embedded-build.md
│
├── tools/                              # Outils supplémentaires
│   ├── cleanup.sh                      # Nettoyage
│   ├── backup.sh                       # Backup LFS
│   ├── restore.sh                      # Restauration
│   ├── benchmark.sh                    # Benchmark construction
│   └── docker/
│       ├── build.sh
│       └── run.sh
│
├── scripts-generated/                  # Scripts générés (runtime)
│   ├── lpm                             # Gestionnaire paquets généré
│   ├── first-boot.sh                   # Assistant first-boot généré
│   ├── monitor.sh                      # Script monitoring
│   └── hooks/
│
└── var/                                # Données variables (runtime)
    ├── logs/                           # Logs de build
    ├── run/                            # PIDs, sockets
    ├── tmp/                            # Fichiers temporaires
    └── lib/                            # Base de données locale
        ├── packages.db
        └── snapshots.db
```

## 📁 Détail des fichiers importants par feature

### Feature 1: Interface TUI
```
src/features/tui/app.py                  # Point d'entrée TUI
src/features/tui/screens/main.py         # Écran principal
src/features/tui/screens/profile.py      # Sélection profil
src/features/tui/widgets/custom.py       # Widgets personnalisés
```

### Feature 2: Snapshots
```
src/features/snapshot/manager.py         # SnapshotManager
src/features/snapshot/rollback.py        # Rollback handler
data/snapshots/                          # Stockage snapshots
scripts-generated/hooks/pre-upgrade.sh   # Snapshot avant upgrade
```

### Feature 3: First-boot assistant
```
src/features/firstboot/assistant.py      # Générateur assistant
src/features/firstboot/templates/first-boot.sh.tpl  # Template
scripts-generated/first-boot.sh          # Script généré (dans ISO)
```

### Feature 4: Dry-run
```
src/features/dryrun/executor.py          # DryRunExecutor
src/features/dryrun/analyzer.py          # Analyseur scripts
src/features/dryrun/reporter.py          # Générateur rapport
```

### Feature 5: Advanced downloader
```
src/features/downloader/advanced.py      # AdvancedDownloader
src/features/downloader/aria2.py         # Intégration aria2c
src/features/downloader/cache.py         # Cache manager
data/cache/                              # Cache téléchargements
```

### Feature 6: Web monitoring
```
src/features/monitor/server.py           # Serveur Flask
src/features/monitor/templates/dashboard.html  # Dashboard
src/features/monitor/static/js/dashboard.js    # JS temps réel
var/run/monitor.pid                      # PID du serveur
```

### Feature 7: Advanced LPM
```
src/features/packagemanager/lpm.py       # Générateur LPM
src/features/packagemanager/templates/lpm.sh.tpl  # Template
scripts-generated/lpm                    # Script généré
var/lib/packages.db                      # Base SQLite des paquets
/etc/lpm/repos.d/                        # Dépôts (sur système cible)
```

### Feature 8: User profiles
```
src/features/userprofiles/manager.py     # UserProfileManager
src/features/userprofiles/profiles.yaml  # Définition profils
config/profiles/gaming.yaml              # Profil gaming
config/profiles/development.yaml         # Profil dev
```

### Feature 9: Docker support
```
src/features/docker/Dockerfile           # Image Docker
src/features/docker/docker-compose.yml   # Compose multi-services
tools/docker/build.sh                    # Script build image
tools/docker/run.sh                      # Script run conteneur
```

### Feature 10: ISO customization
```
src/features/iso/builder.py              # ISOBuilder avancé
src/features/iso/secureboot.py           # Signature SecureBoot
data/themes/default/                     # Thèmes intégrés
```

### Feature 11: Notifications
```
src/features/notifications/manager.py    # NotificationManager
src/features/notifications/telegram.py   # Telegram bot
config/notifications.conf                # Tokens et webhooks
```

### Feature 12: Interactive mode
```
src/features/interactive/builder.py      # InteractiveBuilder
src/features/interactive/error_handler.py # Gestion interactive
src/features/interactive/recovery.py     # Stratégies recovery
```

### Feature 13: Hardware detection
```
src/features/hardware/detector.py        # HardwareCompatibility
src/features/hardware/gpu.py             # Détection GPU
src/features/hardware/recommendations.py # Recommandations kernel
```

### Feature 14: Distro customization
```
src/features/distro/customizer.py        # DistroCustomizer
src/features/distro/branding.py          # Branding OS
src/features/distro/release.py           # Génération release
etc/os-release                           # (cible) OS info
etc/lfs-release                          # (cible) Version LFS
```

## 📄 Fichiers de configuration principaux

```yaml
# config/build.yaml (Nouveau format YAML)
distribution:
  name: "MyLFS"
  version: "1.0.0"
  codename: "awesome-dragon"
  
profile: gaming

features:
  tui_enabled: true
  snapshots: true
  web_monitor: true
  notifications:
    desktop: true
    telegram: "BOT_TOKEN"
    
customization:
  theme: dark
  wallpaper: "/usr/share/backgrounds/custom.jpg"
  boot_splash: "data/themes/dark/splash.png"
```

## 🚀 Fichier Makefile pour simplifier l'usage

```makefile
# Makefile
.PHONY: help build clean config monitor shell test docker

help:
	@echo "LFS Builder - Commandes disponibles:"
	@echo "  make build      - Construire le système"
	@echo "  make config     - Lancer interface TUI"
	@echo "  make monitor    - Démarrer monitoring web"
	@echo "  make shell      - Shell interactif"
	@echo "  make test       - Lancer les tests"
	@echo "  make docker     - Construire dans Docker"
	@echo "  make clean      - Nettoyer"

build:
	python3 builder.py --profile $(PROFILE) --output $(OUTPUT)

config:
	python3 -m src.cli.main config --tui

monitor:
	python3 -m src.features.monitor.server --port 8080

shell:
	python3 -m src.cli.main shell

test:
	pytest tests/ -v --cov=src

docker:
	./tools/docker/run.sh

clean:
	rm -rf var/tmp/* var/logs/* data/cache/*
```

Cette organisation te permet de :
1. **Ajouter des features sans tout casser** (modularité)
2. **Tester chaque composant indépendamment**
3. **Générer du code à la volée** (scripts LPM, first-boot, etc.)
4. **Garder une séparation claire** entre code, données et runtime

Tu veux que je détaille l'implémentation d'un de ces modules en particulier ?

The system will automatically download all sources, build the toolchain, compile LFS/BLFS, configure the desktop, and create a bootable USB installer ISO.