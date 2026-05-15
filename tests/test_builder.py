#!/usr/bin/env python3
"""
Tests for LFSBuilder class
"""

import pytest
import json
from unittest.mock import patch, MagicMock, call
from pathlib import Path
from builder import LFSBuilder


class TestLFSBuilder:
    """Test LFSBuilder class"""

    def test_init(self, temp_dir, mock_config_file):
        """Test initialization"""
        output_dir = temp_dir / "lfs-build"
        builder = LFSBuilder(
            profile="xfce",
            output_dir=output_dir,
            config_file=mock_config_file
        )

        assert builder.profile == "xfce"
        assert builder.output_dir == output_dir
        assert builder.profile_config['desktop'] == 'xfce'

    def test_is_cross_compile_default(self, builder):
        """Test cross-compilation disabled by default"""
        assert builder.is_cross_compile() is False

    def test_get_target_architecture_default(self, builder):
        """Test default target architecture"""
        assert builder.get_target_architecture() == "x86_64"

    def test_get_init_system_default(self, builder):
        """Test default init system"""
        assert builder.get_init_system() == "sysvinit"

    def test_get_init_system_systemd(self, builder):
        """Test systemd init system"""
        builder.config.set('init_system.choice', 'systemd')
        assert builder.get_init_system() == "systemd"

    def test_get_init_system_normalize_sysv(self, builder):
        """Test normalization of 'sysv' to 'sysvinit'"""
        builder.config.set('init_system.choice', 'sysv')
        assert builder.get_init_system() == "sysvinit"

    def test_get_qemu_user_aarch64(self, builder):
        """Test QEMU user mapping for aarch64"""
        with patch.object(builder, 'is_cross_compile', return_value=True):
            with patch.object(builder, 'get_target_architecture', return_value='aarch64'):
                qemu = builder.get_qemu_user()
                assert qemu == 'qemu-aarch64-static'

    def test_check_prerequisites_linux(self, builder):
        """Test prerequisites check on Linux"""
        with patch('platform.system', return_value='Linux'):
            with patch('shutil.which', return_value=True):
                with patch('os.path.exists', return_value=False):
                    with patch('shutil.disk_usage', return_value=MagicMock(free=100 * 1024**3)):
                        result = builder.check_prerequisites()
                        assert result is True

    def test_check_prerequisites_missing_commands(self, builder):
        """Test prerequisites with missing commands"""
        with patch('platform.system', return_value='Linux'):
            with patch('shutil.which', return_value=False):
                with patch('os.path.exists', return_value=False):
                    result = builder.check_prerequisites()
                    assert result is False

    def test_prepare_environment_creates_directories(self, builder, temp_dir):
        """Test environment preparation creates directories"""
        builder.output_dir = temp_dir / "test-build"
        result = builder.prepare_environment()

        assert result is True
        assert (builder.output_dir / 'sources').exists()
        assert (builder.output_dir / 'logs').exists()
        assert (builder.output_dir / 'image').exists()
        assert (builder.output_dir / 'build_info.json').exists()

    def test_prepare_environment_creates_build_info(self, builder):
        """Test build info JSON creation"""
        builder.prepare_environment()

        build_info_path = builder.output_dir / 'build_info.json'
        assert build_info_path.exists()

        with open(build_info_path, 'r') as f:
            build_info = json.load(f)

        assert build_info['profile'] == builder.profile
        assert build_info['init_system'] == builder.get_init_system()
        assert 'build_date' in build_info

    def test_get_build_stages_default(self, builder):
        """Test build stages for default profile"""
        stages = builder.get_build_stages()

        # Should contain core stages
        stage_names = [s[0] for s in stages]
        assert 'host-check' in stage_names
        assert 'host-prepare' in stage_names
        assert 'lfs-basic' in stage_names
        assert 'lfs-system' in stage_names
        assert 'init-system' in stage_names
        assert 'service-abstraction' in stage_names

    def test_get_build_stages_with_desktop(self, builder):
        """Test build stages with desktop enabled"""
        builder.profile_config['desktop'] = 'xfce'
        stages = builder.get_build_stages()

        stage_names = [s[0] for s in stages]
        assert 'desktop' in stage_names
        assert 'applications' in stage_names
        assert 'configure-desktop' in stage_names

    def test_get_build_stages_with_java_dev(self, builder):
        """Test build stages with Java development enabled"""
        builder.profile_config['java_dev'] = True
        stages = builder.get_build_stages()

        stage_names = [s[0] for s in stages]
        assert 'java-dev' in stage_names

    def test_get_build_stages_with_security(self, builder):
        """Test build stages with security hardening"""
        builder.profile_config['security_hardening'] = True
        stages = builder.get_build_stages()

        stage_names = [s[0] for s in stages]
        assert 'security' in stage_names

    def test_get_build_stages_with_privacy(self, builder):
        """Test build stages with privacy tools"""
        builder.profile_config['privacy_tools'] = True
        stages = builder.get_build_stages()

        stage_names = [s[0] for s in stages]
        assert 'privacy' in stage_names

    def test_get_build_stages_cross_compile(self, builder):
        """Test build stages with cross-compilation"""
        with patch.object(builder, 'is_cross_compile', return_value=True):
            stages = builder.get_build_stages()
            stage_names = [s[0] for s in stages]
            assert 'qemu-setup' in stage_names

    def test_get_build_stages_uboot(self, builder):
        """Test build stages with U-Boot bootloader"""
        builder.config.set('bootloader.type', 'uboot')
        stages = builder.get_build_stages()

        stage_names = [s[0] for s in stages]
        assert 'uboot' in stage_names

    def test_get_env_variables(self, builder):
        """Test environment variables generation"""
        env = builder._get_env()

        assert 'LFS' in env
        assert 'LFS_TGT' in env
        assert 'MAKEFLAGS' in env
        assert 'PROFILE' in env
        assert 'INIT_SYSTEM' in env
        assert 'SYSVINIT_STYLE' in env
        assert 'LIVE_SYSTEM' in env

    def test_get_env_cross_compile(self, builder):
        """Test environment variables for cross-compilation"""
        with patch.object(builder, 'is_cross_compile', return_value=True):
            with patch.object(builder, 'get_target_architecture', return_value='aarch64'):
                env = builder._get_env()

                assert env['CROSS_COMPILE'] == '1'
                assert env['ARCH'] == 'aarch64'
                assert 'CROSS_PREFIX' in env
                assert 'QEMU_USER' in env
                assert 'SYSROOT' in env

    @patch('subprocess.run')
    def test_build_success(self, mock_run, builder):
        """Test successful build"""
        mock_run.return_value = MagicMock(returncode=0)

        with patch.object(builder.executor, 'find_script', return_value=Path("script.sh")):
            result = builder.build()

            assert result is True

    @patch('subprocess.run')
    def test_build_failure(self, mock_run, builder):
        """Test build failure"""
        mock_run.return_value = MagicMock(returncode=1)

        with patch.object(builder.executor, 'find_script', return_value=Path("script.sh")):
            result = builder.build()

            assert result is False

    @patch('subprocess.run')
    def test_build_resume_from_stage(self, mock_run, builder):
        """Test resuming build from specific stage"""
        mock_run.return_value = MagicMock(returncode=0)

        with patch.object(builder.executor, 'find_script', return_value=Path("script.sh")):
            result = builder.build(resume_from="lfs-system")

            assert result is True

    def test_create_writable_media_no_iso(self, builder, mock_logger):
        """Test writing USB without ISO"""
        with patch.object(builder, 'logger', mock_logger):
            result = builder.create_writable_media()

            assert result is False
            mock_logger.error.assert_called()