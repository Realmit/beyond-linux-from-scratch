import pytest
import json
import tempfile
from unittest.mock import patch, MagicMock
from pathlib import Path
import logging

from builder import LFSBuilder, ScriptExecutor, SourceDownloader


@pytest.fixture
def builder():
    output_dir = Path(tempfile.mkdtemp())
    config_file = Path("config/build.conf")
    config_file.parent.mkdir(parents=True, exist_ok=True)
    if not config_file.exists():
        with open(config_file, 'w') as f:
            json.dump({
                "lfs_version": "13.0",
                "blfs_version": "13.0",
                "architecture": "x86_64"
            }, f)
    return LFSBuilder(profile='minimal', output_dir=output_dir, config_file=config_file)


@pytest.fixture
def executor(builder):
    return builder.executor


@pytest.fixture
def downloader(builder):
    return builder.downloader


@pytest.fixture
def stages():
    return [
        ('host-check', 'host/01-check-host.sh'),
        ('host-prepare', 'host/02-prepare-host.sh')
    ]


class TestCheckPrerequisites:

    def test_unsupported_os(self, builder):
        builder.system = 'Unknown'
        assert builder.check_prerequisites() is False

    def test_windows_os(self, builder):
        builder.system = 'Windows'
        with patch('shutil.which', return_value=True):
            with patch('shutil.disk_usage', return_value=MagicMock(free=100*1024**3)):
                assert builder.check_prerequisites() is True

    def test_missing_commands(self, builder):
        builder.system = 'Linux'
        with patch('shutil.which', return_value=None):
            assert builder.check_prerequisites() is False

    def test_low_disk_space(self, builder, caplog):
        builder.system = 'Linux'
        with patch('shutil.which', return_value=True):
            with patch('shutil.disk_usage', return_value=MagicMock(free=10*1024**3)):
                with caplog.at_level(logging.WARNING):
                    result = builder.check_prerequisites()
                assert result is True
                assert "Low disk space" in caplog.text

    def test_cross_compile_missing_toolchain(self, builder):
        builder.system = 'Linux'
        builder.config.set('cross_compile', True)
        builder.config.set('architecture', 'aarch64')
        def which_side_effect(cmd):
            if cmd == 'aarch64-linux-gnu-gcc':
                return None
            return '/usr/bin/' + cmd
        with patch('shutil.which', side_effect=which_side_effect):
            with patch('shutil.disk_usage', return_value=MagicMock(free=100*1024**3)):
                assert builder.check_prerequisites() is True

    def test_macos_non_docker(self, builder):
        with patch('os.path.exists', return_value=False):
            with patch('shutil.which', return_value=True):
                with patch('shutil.disk_usage', return_value=MagicMock(free=100*1024**3)):
                    assert builder.check_prerequisites() is True

    def test_build_resume_from(self, builder):
        with patch.object(builder.executor, 'resume_from', return_value=True) as mock_resume:
            builder.build(resume_from='host-check')
            mock_resume.assert_called_once_with('host-check', builder.get_build_stages())

    def test_build_stage_failure(self, builder):
        with patch.object(builder.executor, 'run_script', return_value=False):
            with patch.object(builder, 'get_build_stages', return_value=[('stage1', 'script.sh')]):
                assert builder.build() is False

    def test_find_script_not_found(self, executor):
        assert executor.find_script('nonexistent.sh') is None

    def test_resume_from_valid_stage(self, executor, stages):
        with patch.object(executor, 'run_script', return_value=True) as mock_run:
            executor.resume_from('host-check', stages)
            mock_run.assert_called()

    def test_download_sources_file_not_found(self, builder):
        with patch('pathlib.Path.exists', return_value=False):
            assert builder.download_sources() is False

    def test_create_writable_media_no_iso(self, builder):
        with patch('pathlib.Path.exists', return_value=False):
            assert builder.create_writable_media() is False

    def test_download_all_retries_fail(self, downloader):
        with patch('urllib.request.urlretrieve', side_effect=Exception('Network error')):
            result = downloader.download('http://example.com/file', 'file')
            assert result is False

    def test_run_script_exception(self, executor):
        with patch('subprocess.run', side_effect=ValueError('Something went wrong')):
            with patch('pathlib.Path.exists', return_value=True):
                with patch('pathlib.Path.chmod'):
                    result = executor.run_script('script.sh', 'stage')
                    assert result is False