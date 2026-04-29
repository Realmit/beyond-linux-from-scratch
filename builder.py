#!/usr/bin/env python3
"""
LFS/BLFS Builder - Main orchestrator
Works on Linux, macOS, and Windows (WSL2)
Version: 3.0.0 - Added Security Hardening, Privacy Tools, Init System Choice
"""

import os
import sys
import json
import argparse
import subprocess
import platform
import shutil
import hashlib
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Tuple
import logging
import tempfile
import urllib.request
from concurrent.futures import ThreadPoolExecutor

# ============================================================================
# CONFIGURATION CLASSES
# ============================================================================

class LFSConfig:
    """LFS Builder Configuration Manager"""

    def __init__(self, config_file: Path):
        self.config_file = config_file
        self.data = self.load()

    def load(self) -> Dict:
        """Load configuration from JSON file"""
        if not self.config_file.exists():
            self.data = self.get_default_config()
            self.save()
        else:
            with open(self.config_file, 'r') as f:
                self.data = json.load(f)
        return self.data

    def save(self):
        """Save configuration to JSON file"""
        with open(self.config_file, 'w') as f:
            json.dump(self.data, f, indent=2)

    def get_default_config(self) -> Dict:
        """Return default configuration"""
        return {
            "lfs_version": "12.1",
            "blfs_version": "12.1",
            "architecture": "x86_64",
            "target_triplet": "x86_64-lfs-linux-gnu",
            "build_threads": os.cpu_count(),

            "init_system": {
                "choice": "systemd",
                "service_style": "classic",
                "parallel_startup": True,
                "auto_restart": True,
                "default_runlevel": 5,
                "service_timeout": 5,
                "max_parallel": 4
            },

            "package_manager": {
                "enabled": True,
                "name": "lpm",
                "version": "1.0.0",
                "repositories": ["official", "community"],
                "auto_clean": True,
                "dependency_resolution": True
            },

            "java_dev": {
                "enabled": False,
                "version": "21.0.6",
                "distribution": "temurin",
                "tools": ["maven", "gradle", "tomcat", "jenkins"],
                "optimizations": True,
                "demo_projects": True
            },

            "desktop": {
                "type": "xfce",
                "display_manager": "lightdm",
                "theme": "adwaita",
                "extras": ["firefox", "libreoffice", "gimp", "vlc"]
            },

            "security": {
                "kernel_hardening": True,
                "firewall": {"enabled": True, "backend": "nftables", "allow_ssh": True},
                "privacy": {"disable_telemetry": True, "clear_tmp_on_boot": True},
                "fail2ban": {"enabled": True, "ban_time": 3600},
                "audit": {"enabled": True, "monitor_files": ["/etc/passwd", "/etc/shadow"]},
                "user_hardening": {"password_min_length": 12, "disable_root_login": True},
                "encryption": {"encrypted_swap": True, "swap_size_mb": 2048},
                "hids": {"enabled": True, "daily_check": True},
                "daily_scans": {"enabled": True, "rootkit_check": True}
            },

            "filesystem": {
                "type": "ext4",
                "size_mb": 10240,
                "swap_mb": 2048,
                "boot_mb": 512
            },

            "kernel": {
                "version": "6.6.14",
                "config": "config/kernel-config",
                "modules": ["ext4", "xfs", "nvme", "virtio", "usb_storage"]
            },

            "locale": "en_US.UTF-8",
            "timezone": "America/New_York",
            "hostname": "lfs-desktop",
            "keyboard_layout": "us",

            "users": [
                {"name": "lfsuser", "groups": ["wheel", "audio", "video", "storage"], "sudo": True}
            ],

            "network": {
                "dhcp": True,
                "dns_servers": ["8.8.8.8", "8.8.4.4"],
                "enable_ipv6": True
            },

            "custom_scripts": ["packages/custom-scripts/post-install.sh"],

            "repositories": [
                "https://www.linuxfromscratch.org/lfs/view/stable/wget-list",
                "https://www.linuxfromscratch.org/blfs/view/stable/wget-list"
            ],

            "build_options": {
                "parallel_build": True,
                "keep_build_dirs": False,
                "strip_binaries": True,
                "checksum_verification": True,
                "verbose_logging": False
            },

            "logging": {
                "level": "INFO",
                "max_size_mb": 100,
                "max_files": 10
            }
        }

    def get(self, key: str, default=None):
        """Get configuration value by dot notation key"""
        keys = key.split('.')
        value = self.data
        for k in keys:
            if isinstance(value, dict):
                value = value.get(k, default)
            else:
                return default
        return value

    def set(self, key: str, value):
        """Set configuration value by dot notation key"""
        keys = key.split('.')
        target = self.data
        for k in keys[:-1]:
            if k not in target:
                target[k] = {}
            target = target[k]
        target[keys[-1]] = value
        self.save()


# ============================================================================
# PROFILE MANAGER
# ============================================================================

class ProfileManager:
    """Manage build profiles (minimal, xfce, gnome, java-dev, security, full, etc.)"""

    PROFILES = {
        'minimal': {
            'description': 'Minimal command-line only system',
            'size_gb': 1,
            'build_time_hours': 2,
            'packages': ['base', 'network', 'ssh'],
            'desktop': None,
            'java_dev': False,
            'package_manager': True,
            'security_hardening': False,
            'privacy_tools': False
        },
        'xfce': {
            'description': 'XFCE desktop environment',
            'size_gb': 4,
            'build_time_hours': 4,
            'packages': ['base', 'network', 'ssh', 'xorg', 'xfce', 'apps'],
            'desktop': 'xfce',
            'java_dev': False,
            'package_manager': True,
            'security_hardening': True,
            'privacy_tools': False
        },
        'gnome': {
            'description': 'GNOME desktop environment',
            'size_gb': 8,
            'build_time_hours': 8,
            'packages': ['base', 'network', 'ssh', 'xorg', 'gnome', 'apps'],
            'desktop': 'gnome',
            'java_dev': False,
            'package_manager': True,
            'security_hardening': True,
            'privacy_tools': False
        },
        'java-dev': {
            'description': 'Java development environment with XFCE',
            'size_gb': 10,
            'build_time_hours': 6,
            'packages': ['base', 'network', 'ssh', 'xorg', 'xfce', 'apps', 'java', 'maven', 'gradle', 'tomcat', 'jenkins', 'docker'],
            'desktop': 'xfce',
            'java_dev': True,
            'package_manager': True,
            'security_hardening': True,
            'privacy_tools': False
        },
        'secure': {
            'description': 'Security-hardened system with privacy tools',
            'size_gb': 6,
            'build_time_hours': 5,
            'packages': ['base', 'network', 'ssh', 'xorg', 'xfce', 'security'],
            'desktop': 'xfce',
            'java_dev': False,
            'package_manager': True,
            'security_hardening': True,
            'privacy_tools': True
        },
        'full': {
            'description': 'Complete system with everything',
            'size_gb': 20,
            'build_time_hours': 12,
            'packages': ['all'],
            'desktop': 'gnome',
            'java_dev': True,
            'package_manager': True,
            'security_hardening': True,
            'privacy_tools': True
        }
    }

    @classmethod
    def get_profile(cls, name: str) -> Dict:
        """Get profile configuration"""
        if name not in cls.PROFILES:
            raise ValueError(f"Unknown profile: {name}. Available: {list(cls.PROFILES.keys())}")
        return cls.PROFILES[name]

    @classmethod
    def list_profiles(cls) -> List[str]:
        """List all available profiles"""
        return list(cls.PROFILES.keys())

    @classmethod
    def get_profile_info(cls, name: str) -> str:
        """Get profile information string"""
        profile = cls.get_profile(name)
        return f"""
Profile: {name}
  Description: {profile['description']}
  Size: ~{profile['size_gb']} GB
  Build time: ~{profile['build_time_hours']} hours
  Desktop: {profile['desktop'] or 'None'}
  Java Dev: {profile['java_dev']}
  Package Manager: {profile['package_manager']}
  Security Hardening: {profile.get('security_hardening', False)}
  Privacy Tools: {profile.get('privacy_tools', False)}
"""


# ============================================================================
# SOURCE DOWNLOADER
# ============================================================================

class SourceDownloader:
    """Download and verify LFS/BLFS sources"""

    def __init__(self, sources_dir: Path, logger: logging.Logger):
        self.sources_dir = sources_dir
        self.logger = logger
        self.session = self._create_session()

    def _create_session(self):
        """Create urllib session with retry logic"""
        opener = urllib.request.build_opener()
        opener.addheaders = [('User-Agent', 'LFS-Builder/3.0')]
        return opener

    def download(self, url: str, filename: Optional[str] = None) -> bool:
        """Download a file with progress indication"""
        if filename is None:
            filename = url.split('/')[-1]

        dest = self.sources_dir / filename

        if dest.exists():
            self.logger.info(f"Already exists: {filename}")
            return True

        self.logger.info(f"Downloading: {filename}")

        try:
            urllib.request.urlretrieve(url, dest, self._reporthook)
            print()  # New line after progress
            return True
        except Exception as e:
            self.logger.error(f"Failed to download {url}: {e}")
            return False

    def _reporthook(self, blocknum, blocksize, totalsize):
        """Download progress callback"""
        if totalsize <= 0:
            return
        percent = int(blocknum * blocksize * 100 / totalsize)
        if percent % 10 == 0:
            sys.stdout.write(f"\r  Progress: {percent}%")
            sys.stdout.flush()

    def download_from_list(self, list_file: Path, parallel: int = 4) -> bool:
        """Download multiple sources in parallel"""
        if not list_file.exists():
            self.logger.error(f"Sources list not found: {list_file}")
            return False

        urls = []
        with open(list_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#'):
                    urls.append(line)

        self.logger.info(f"Downloading {len(urls)} sources with {parallel} threads")

        with ThreadPoolExecutor(max_workers=parallel) as executor:
            futures = [executor.submit(self.download, url) for url in urls]
            results = [f.result() for f in futures]

        success = all(results)
        if success:
            self.logger.info("All sources downloaded successfully")
        else:
            self.logger.warning("Some sources failed to download")

        return success

    def verify_checksums(self, checksum_file: Path) -> bool:
        """Verify downloaded files against checksums"""
        if not checksum_file.exists():
            self.logger.warning("No checksum file found, skipping verification")
            return True

        all_valid = True
        with open(checksum_file, 'r') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue

                parts = line.split()
                if len(parts) != 2:
                    continue

                expected_md5, filename = parts
                filepath = self.sources_dir / filename

                if not filepath.exists():
                    self.logger.warning(f"Missing file: {filename}")
                    all_valid = False
                    continue

                actual_md5 = hashlib.md5(filepath.read_bytes()).hexdigest()
                if actual_md5 != expected_md5:
                    self.logger.error(f"Checksum mismatch: {filename}")
                    all_valid = False

        return all_valid


# ============================================================================
# SCRIPT EXECUTOR
# ============================================================================

class ScriptExecutor:
    """Execute build scripts with proper error handling"""

    def __init__(self, env: Dict, output_dir: Path, logger: logging.Logger):
        self.env = env
        self.output_dir = output_dir
        self.logger = logger
        self.completed_stages = []

    def run_script(self, script_path: Path, stage_name: str, timeout: int = 7200) -> bool:
        """Run a single build script"""
        self.logger.info(f"Running stage: {stage_name}")

        if not script_path.exists():
            self.logger.error(f"Script not found: {script_path}")
            return False

        script_path.chmod(0o755)

        log_file = self.output_dir / 'logs' / f"{stage_name}.log"

        try:
            with open(log_file, 'w') as log:
                result = subprocess.run(
                    [str(script_path)],
                    env={**os.environ, **self.env},
                    stdout=log,
                    stderr=subprocess.STDOUT,
                    text=True,
                    timeout=timeout
                )

            if result.returncode == 0:
                self.logger.info(f"Stage completed: {stage_name}")
                self.completed_stages.append(stage_name)
                return True
            else:
                self.logger.error(f"Stage failed: {stage_name} (exit code: {result.returncode})")
                self.logger.info(f"Check log: {log_file}")
                return False

        except subprocess.TimeoutExpired:
            self.logger.error(f"Stage timed out after {timeout} seconds: {stage_name}")
            return False
        except Exception as e:
            self.logger.error(f"Exception running stage {stage_name}: {e}")
            return False

    def resume_from(self, resume_stage: str, stages: List[Tuple[str, Path]]) -> bool:
        """Resume build from a specific stage"""
        start_index = 0
        for i, (stage_name, _) in enumerate(stages):
            if stage_name == resume_stage:
                start_index = i
                break

        self.logger.info(f"Resuming build from stage: {resume_stage}")

        for stage_name, script_path in stages[start_index:]:
            if not self.run_script(script_path, stage_name):
                return False

        return True


# ============================================================================
# USB WRITER
# ============================================================================

class USBWriter:
    """Write bootable ISO to USB drive"""

    @staticmethod
    def list_devices() -> List[str]:
        """List available USB devices"""
        devices = []

        if platform.system() == "Linux":
            result = subprocess.run(['lsblk', '-d', '-o', 'NAME,SIZE,MODEL', '-l'],
                                    capture_output=True, text=True)
            for line in result.stdout.split('\n')[1:]:
                if line.strip():
                    devices.append(line.strip())
        elif platform.system() == "Darwin":
            result = subprocess.run(['diskutil', 'list'], capture_output=True, text=True)
            for line in result.stdout.split('\n'):
                if '/dev/disk' in line and 'external' in line.lower():
                    devices.append(line.strip())

        return devices

    @staticmethod
    def write_iso(iso_path: Path, device: str, logger: logging.Logger) -> bool:
        """Write ISO to USB device"""
        if not iso_path.exists():
            logger.error(f"ISO not found: {iso_path}")
            return False

        logger.warning(f"This will overwrite {device}")
        response = input("Continue? (yes/no): ")

        if response.lower() != 'yes':
            logger.info("Operation cancelled")
            return False

        system = platform.system()

        if system == "Linux":
            cmd = ['sudo', 'dd', f'if={iso_path}', f'of={device}', 'bs=4M', 'status=progress']
        elif system == "Darwin":
            raw_device = device.replace('disk', 'rdisk')
            cmd = ['sudo', 'dd', f'if={iso_path}', f'of={raw_device}', 'bs=4m']
        else:
            logger.error("USB writing not supported on this platform")
            return False

        try:
            subprocess.run(cmd, check=True)
            logger.info(f"Successfully written to {device}")
            return True
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to write ISO: {e}")
            return False


# ============================================================================
# MAIN BUILDER CLASS
# ============================================================================

class LFSBuilder:
    """Main orchestrator for LFS/BLFS build process"""

    def __init__(self, profile: str, output_dir: Path, config_file: Path):
        self.profile = profile
        self.output_dir = Path(output_dir)
        self.config = LFSConfig(config_file)
        self.system = platform.system()
        self.logger = self.setup_logging()
        self.profile_config = ProfileManager.get_profile(profile)

        # Apply profile settings to config
        self._apply_profile_settings()

        # Initialize components
        self.downloader = SourceDownloader(self.output_dir / 'sources', self.logger)
        self.executor = ScriptExecutor(self._get_env(), self.output_dir, self.logger)

    def _apply_profile_settings(self):
        """Apply profile-specific settings to configuration"""
        if self.profile_config.get('desktop'):
            self.config.set('desktop.type', self.profile_config['desktop'])

        self.config.set('java_dev.enabled', self.profile_config.get('java_dev', False))
        self.config.set('package_manager.enabled', self.profile_config.get('package_manager', True))

        # Apply security settings based on profile
        if self.profile_config.get('security_hardening', False):
            self.config.set('security.kernel_hardening', True)
            self.config.set('security.firewall.enabled', True)
            self.config.set('security.fail2ban.enabled', True)
            self.config.set('security.audit.enabled', True)
            self.config.set('security.hids.enabled', True)

        if self.profile_config.get('privacy_tools', False):
            self.config.set('security.privacy.disable_telemetry', True)
            self.config.set('security.privacy_tools.dnscrypt', True)
            self.config.set('security.privacy_tools.wireguard', True)

    def get_init_system(self) -> str:
        """Get init system choice from config"""
        init_choices = ['systemd', 'sysv', 'openrc', 'runit', 's6']
        init = self.config.get('init_system.choice', 'systemd')

        if init not in init_choices:
            self.logger.warning(f"Unknown init system: {init}, using systemd")
            init = 'systemd'

        return init

    def _get_env(self) -> Dict:
        """Get environment variables for scripts"""
        return {
            'LFS': str(self.output_dir / 'image'),
            'LFS_TGT': self.config.get('target_triplet'),
            'MAKEFLAGS': f"-j{self.config.get('build_threads', os.cpu_count())}",
            'PROFILE': self.profile,
            'INIT_SYSTEM': self.get_init_system(),
            'SERVICE_STYLE': self.config.get('init_system.service_style', 'classic'),
            'PARALLEL_STARTUP': str(self.config.get('init_system.parallel_startup', True)).lower(),
            'AUTO_RESTART': str(self.config.get('init_system.auto_restart', True)).lower(),
            'JAVA_DEV': str(self.profile_config.get('java_dev', False)).lower(),
            'LPM_ENABLED': str(self.profile_config.get('package_manager', True)).lower(),
            'SECURITY_HARDENING': str(self.profile_config.get('security_hardening', False)).lower(),
            'PRIVACY_TOOLS': str(self.profile_config.get('privacy_tools', False)).lower(),
            'LC_ALL': 'POSIX'
        }

    def setup_logging(self) -> logging.Logger:
        """Setup logging configuration"""
        log_dir = self.output_dir / 'logs'
        log_dir.mkdir(parents=True, exist_ok=True)

        log_level = getattr(logging, self.config.get('logging.level', 'INFO').upper())

        logging.basicConfig(
            level=log_level,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(log_dir / 'build.log'),
                logging.StreamHandler()
            ]
        )
        return logging.getLogger(__name__)

    def check_prerequisites(self) -> bool:
        """Check system prerequisites based on platform"""
        self.logger.info(f"Checking prerequisites on {self.system}")

        if self.system == "Linux":
            required_cmds = ['bash', 'gcc', 'make', 'bison', 'gawk', 'm4', 'texinfo', 'wget', 'tar', 'gzip']
            required_space = 50
        elif self.system == "Darwin":
            required_cmds = ['bash', 'docker', 'make', 'gawk', 'm4']
            required_space = 60
            self.logger.info("macOS detected - Docker will be used for building")
        elif self.system == "Windows":
            required_cmds = ['wsl', 'bash']
            required_space = 60
            self.logger.info("Windows detected - WSL2 required")
        else:
            self.logger.error(f"Unsupported OS: {self.system}")
            return False

        missing = []
        for cmd in required_cmds:
            if not shutil.which(cmd):
                missing.append(cmd)

        if missing:
            self.logger.error(f"Missing commands: {', '.join(missing)}")
            return False

        free_space = shutil.disk_usage(self.output_dir).free // (1024**3)
        if free_space < required_space:
            self.logger.warning(f"Low disk space: {free_space}GB (need {required_space}GB)")

        self.logger.info("Prerequisites check passed")
        return True

    def prepare_environment(self) -> bool:
        """Prepare build environment directories"""
        self.logger.info("Preparing build environment")

        directories = [
            self.output_dir,
            self.output_dir / 'sources',
            self.output_dir / 'tools',
            self.output_dir / 'logs',
            self.output_dir / 'image',
            self.output_dir / 'cache',
            self.output_dir / 'backups'
        ]

        for d in directories:
            d.mkdir(parents=True, exist_ok=True)

        build_info = {
            'profile': self.profile,
            'build_date': datetime.now().isoformat(),
            'lfs_version': self.config.get('lfs_version'),
            'blfs_version': self.config.get('blfs_version'),
            'init_system': self.get_init_system(),
            'system': self.system,
            'cpu_cores': os.cpu_count(),
            'python_version': sys.version
        }

        with open(self.output_dir / 'build_info.json', 'w') as f:
            json.dump(build_info, f, indent=2)

        self.logger.info("Environment prepared")
        return True

    def download_sources(self) -> bool:
        """Download all required sources"""
        self.logger.info("Downloading sources")

        sources_list = Path('packages/sources.list')
        checksum_file = Path('packages/md5sums')

        if not sources_list.exists():
            self.logger.error(f"Sources list not found: {sources_list}")
            return False

        success = self.downloader.download_from_list(sources_list, parallel=4)

        if not success:
            self.logger.warning("Some downloads failed, continuing with available sources")

        if checksum_file.exists():
            self.downloader.verify_checksums(checksum_file)

        return True

    def get_build_stages(self) -> List[Tuple[str, Path]]:
        """Get ordered list of build stages"""
        stages = [
            ('host-check', Path('scripts/host/01-check-host.sh')),
            ('host-prepare', Path('scripts/host/02-prepare-host.sh')),
            ('disk-image', Path('scripts/host/03-create-disk-image.sh')),
            ('toolchain', Path('scripts/host/04-build-toolchain.sh')),
            ('lfs-basic', Path('scripts/lfs/05-build-lfs-basic.sh')),
            ('lfs-system', Path('scripts/lfs/06-build-lfs-system.sh')),
            ('init-system', Path('scripts/lfs/06a-init-system.sh')),
            ('service-abstraction', Path('scripts/lfs/06b-service-management.sh')),
            ('configure-lfs', Path('scripts/lfs/07-configure-lfs.sh')),
            ('blfs-base', Path('scripts/blfs/08-build-blfs-base.sh')),
            ('desktop', Path('scripts/blfs/09-build-desktop.sh')),
            ('applications', Path('scripts/blfs/10-build-applications.sh')),
            ('configure-desktop', Path('scripts/blfs/11-configure-desktop.sh')),
        ]

        # Add Java Dev if enabled
        if self.profile_config.get('java_dev', False):
            stages.append(('java-dev', Path('scripts/blfs/12-install-java-dev.sh')))

        # Add Package Manager if enabled
        if self.profile_config.get('package_manager', True):
            stages.append(('package-manager', Path('scripts/blfs/13-create-package-manager.sh')))
            stages.append(('base-packages', Path('scripts/blfs/14-create-base-packages.sh')))

        # Add Security Hardening if enabled
        if self.profile_config.get('security_hardening', False):
            stages.append(('security', Path('scripts/blfs/15-security-hardening.sh')))

        # Add Privacy Tools if enabled
        if self.profile_config.get('privacy_tools', False):
            stages.append(('privacy', Path('scripts/blfs/16-privacy-tools.sh')))

        # Final stages
        stages.extend([
            ('initramfs', Path('scripts/final/12-create-initramfs.sh')),
            ('bootloader', Path('scripts/final/13-create-bootloader.sh')),
            ('installer', Path('scripts/final/14-create-installer.sh'))
        ])

        return stages

    def build(self, resume_from: Optional[str] = None) -> bool:
        """Main build process"""
        self.logger.info(f"Starting LFS build with profile: {self.profile}")
        self.logger.info(f"Init system: {self.get_init_system()}")
        self.logger.info(f"Output directory: {self.output_dir}")

        stages = self.get_build_stages()

        if resume_from:
            return self.executor.resume_from(resume_from, stages)

        total_stages = len(stages)
        for idx, (stage_name, script_path) in enumerate(stages, 1):
            self.logger.info(f"[{idx}/{total_stages}] Processing stage: {stage_name}")
            if not self.executor.run_script(script_path, stage_name):
                self.logger.error(f"Build failed at stage: {stage_name}")
                self.logger.info(f"You can resume with: --resume-from {stage_name}")
                return False

        self.logger.info("=" * 60)
        self.logger.info("BUILD COMPLETED SUCCESSFULLY!")
        self.logger.info("=" * 60)

        iso_path = self.output_dir / 'lfs-installer.iso'
        if iso_path.exists():
            size_mb = iso_path.stat().st_size / (1024 * 1024)
            self.logger.info(f"Installer ISO: {iso_path} ({size_mb:.1f} MB)")

        return True

    def create_writable_media(self, device: Optional[str] = None) -> bool:
        """Create bootable USB media from installer ISO"""
        installer = self.output_dir / 'lfs-installer.iso'

        if not installer.exists():
            self.logger.error("Installer ISO not found. Run build first.")
            return False

        if device:
            return USBWriter.write_iso(installer, device, self.logger)
        else:
            self.logger.info(f"ISO created: {installer}")
            self.logger.info("\nAvailable devices:")
            devices = USBWriter.list_devices()
            for dev in devices:
                self.logger.info(f"  {dev}")
            self.logger.info("\nTo write to USB, run:")
            self.logger.info(f"  python3 builder.py --write-usb /dev/sdX")
            return True


# ============================================================================
# COMMAND LINE INTERFACE
# ============================================================================

def create_parser() -> argparse.ArgumentParser:
    """Create argument parser"""
    parser = argparse.ArgumentParser(
        description='LFS/BLFS Builder - Custom Linux Distribution Builder',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Build with default profile (XFCE)
  python3 builder.py
  
  # Build with Java development profile
  python3 builder.py --profile java-dev --output ./lfs-java
  
  # Build with security hardening
  python3 builder.py --profile secure
  
  # Build full system
  python3 builder.py --profile full --output ./lfs-full
  
  # Resume from failed stage
  python3 builder.py --resume-from desktop
  
  # List available profiles
  python3 builder.py --list-profiles
  
  # Show profile info
  python3 builder.py --profile-info java-dev
  
  # Write ISO to USB
  python3 builder.py --write-usb /dev/sdb
  
  # Clean build directory
  python3 builder.py --clean --output ./lfs-build
        """
    )

    parser.add_argument('--profile', default='xfce',
                        choices=ProfileManager.list_profiles(),
                        help='Build profile to use')

    parser.add_argument('--output', default='./lfs-build',
                        help='Output directory (default: ./lfs-build)')

    parser.add_argument('--config', default='config/build.conf',
                        help='Configuration file path')

    parser.add_argument('--resume-from',
                        help='Resume build from specific stage')

    parser.add_argument('--write-usb', metavar='DEVICE',
                        help='Write ISO to USB device (e.g., /dev/sdb)')

    parser.add_argument('--list-profiles', action='store_true',
                        help='List all available profiles')

    parser.add_argument('--profile-info', metavar='PROFILE',
                        help='Show information about a profile')

    parser.add_argument('--clean', action='store_true',
                        help='Clean build directory')

    parser.add_argument('--verbose', '-v', action='store_true',
                        help='Enable verbose output')

    parser.add_argument('--init', choices=['systemd', 'sysv', 'openrc', 'runit', 's6'],
                        help='Override init system choice')

    return parser


def clean_build_directory(output_dir: Path, logger: logging.Logger) -> bool:
    """Clean build directory"""
    if not output_dir.exists():
        logger.info("Build directory does not exist")
        return True

    response = input(f"Delete {output_dir}? (yes/no): ")
    if response.lower() == 'yes':
        shutil.rmtree(output_dir)
        logger.info(f"Removed: {output_dir}")
        return True
    else:
        logger.info("Clean cancelled")
        return False


def main():
    """Main entry point"""
    parser = create_parser()
    args = parser.parse_args()

    # Handle list-profiles
    if args.list_profiles:
        print("\n" + "=" * 50)
        print("Available LFS Build Profiles")
        print("=" * 50)
        for profile in ProfileManager.list_profiles():
            info = ProfileManager.get_profile(profile)
            print(f"\n  {profile.upper()}")
            print(f"    Description: {info['description']}")
            print(f"    Size: ~{info['size_gb']} GB")
            print(f"    Build time: ~{info['build_time_hours']} hours")
            print(f"    Security: {'Yes' if info.get('security_hardening', False) else 'No'}")
        print()
        return

    # Handle profile-info
    if args.profile_info:
        print(ProfileManager.get_profile_info(args.profile_info))
        return

    # Handle clean
    if args.clean:
        output_dir = Path(args.output)
        logging.basicConfig(level=logging.INFO)
        logger = logging.getLogger(__name__)
        clean_build_directory(output_dir, logger)
        return

    # Initialize builder
    builder = LFSBuilder(
        profile=args.profile,
        output_dir=args.output,
        config_file=args.config
    )

    # Override init system if specified
    if args.init:
        builder.config.set('init_system.choice', args.init)
        builder.logger.info(f"Init system overridden to: {args.init}")

    # Set verbose logging if requested
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    # Display build info
    print("\n" + "=" * 70)
    print(f"LFS/BLFS Builder v3.0")
    print(f"Profile: {args.profile}")
    print(f"Init System: {builder.get_init_system()}")
    print(f"Output: {args.output}")
    print(f"System: {builder.system}")
    print("=" * 70 + "\n")

    print(ProfileManager.get_profile_info(args.profile))

    # Check prerequisites
    if not builder.check_prerequisites():
        sys.exit(1)

    # Prepare environment
    if not builder.prepare_environment():
        sys.exit(1)

    # Download sources
    if not args.resume_from:
        if not builder.download_sources():
            sys.exit(1)

    # Build system
    if not builder.build(resume_from=args.resume_from):
        sys.exit(1)

    # Write to USB if requested
    if args.write_usb:
        builder.create_writable_media(args.write_usb)

    print("\n" + "=" * 70)
    print("✅ BUILD COMPLETED SUCCESSFULLY!")
    print("=" * 70)
    print(f"📀 ISO location: {builder.output_dir}/lfs-installer.iso")
    print("\nNext steps:")
    print("  1. Write ISO to USB: python3 builder.py --write-usb /dev/sdX")
    print("  2. Boot from USB")
    print("  3. Follow installer prompts")
    print("\nSecurity features enabled:" +
          (" ✓" if builder.profile_config.get('security_hardening', False) else ""))
    print()


if __name__ == '__main__':
    main()