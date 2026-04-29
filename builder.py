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