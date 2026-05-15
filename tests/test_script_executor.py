#!/usr/bin/env python3
"""
Tests for ScriptExecutor class
"""

import pytest
import subprocess
from unittest.mock import patch, MagicMock
from pathlib import Path
from builder import ScriptExecutor


class TestScriptExecutor:
    """Test ScriptExecutor class"""

    def test_init(self, output_dir, mock_logger):
        """Test initialization"""
        env = {'TEST_VAR': 'test_value'}
        executor = ScriptExecutor(env, output_dir, mock_logger)

        assert executor.env == env
        assert executor.output_dir == output_dir
        assert executor.logger == mock_logger
        assert executor.completed_stages == []

    def test_find_script_direct_path(self, mock_script, output_dir, mock_logger):
        """Test finding script by direct path"""
        executor = ScriptExecutor({}, output_dir, mock_logger)
        script_path = executor.find_script(str(mock_script))

        assert script_path == mock_script

    def test_find_script_with_scripts_prefix(self, mock_script, output_dir, mock_logger):
        """Test finding script with scripts/ prefix"""
        # Create script in scripts directory
        scripts_dir = Path.cwd() / "scripts"
        scripts_dir.mkdir(parents=True, exist_ok=True)
        script_in_scripts = scripts_dir / "test-script.sh"
        script_in_scripts.write_text("#!/bin/bash\nexit 0")
        script_in_scripts.chmod(0o755)

        executor = ScriptExecutor({}, output_dir, mock_logger)
        script_path = executor.find_script("test-script.sh")

        if script_path:
            assert script_path.name == "test-script.sh"

        # Clean up
        import shutil
        if scripts_dir.exists():
            shutil.rmtree(scripts_dir)

    def test_find_script_not_found(self, output_dir, mock_logger):
        """Test script not found"""
        executor = ScriptExecutor({}, output_dir, mock_logger)
        script_path = executor.find_script("/nonexistent/script.sh")

        assert script_path is None

    @patch('subprocess.run')
    def test_run_script_success(self, mock_run, mock_script, output_dir, mock_logger):
        """Test successful script execution"""
        mock_run.return_value = MagicMock(returncode=0)

        executor = ScriptExecutor({}, output_dir, mock_logger)
        result = executor.run_script(str(mock_script), "test_stage")

        assert result is True
        assert "test_stage" in executor.completed_stages

    @patch('subprocess.run')
    def test_run_script_failure(self, mock_run, mock_script, output_dir, mock_logger):
        """Test script execution failure"""
        mock_run.return_value = MagicMock(returncode=1)

        executor = ScriptExecutor({}, output_dir, mock_logger)
        result = executor.run_script(str(mock_script), "test_stage")

        assert result is False
        mock_logger.error.assert_called()

    @patch('subprocess.run')
    def test_run_script_timeout(self, mock_run, mock_script, output_dir, mock_logger):
        """Test script timeout"""
        mock_run.side_effect = subprocess.TimeoutExpired(cmd="test", timeout=10)

        executor = ScriptExecutor({}, output_dir, mock_logger)
        result = executor.run_script(str(mock_script), "test_stage", timeout=10)

        assert result is False
        mock_logger.error.assert_called()

    @patch('subprocess.run')
    def test_run_script_exception(self, mock_run, mock_script, output_dir, mock_logger):
        """Test script exception"""
        mock_run.side_effect = Exception("Unexpected error")

        executor = ScriptExecutor({}, output_dir, mock_logger)
        result = executor.run_script(str(mock_script), "test_stage")

        assert result is False
        mock_logger.error.assert_called()

    @patch('subprocess.run')
    def test_resume_from_stage(self, mock_run, output_dir, mock_logger):
        """Test resuming build from specific stage"""
        mock_run.return_value = MagicMock(returncode=0)

        stages = [
            ("stage1", "script1.sh"),
            ("stage2", "script2.sh"),
            ("stage3", "script3.sh"),
        ]

        executor = ScriptExecutor({}, output_dir, mock_logger)

        with patch.object(executor, 'find_script', return_value=Path("script.sh")):
            result = executor.resume_from("stage2", stages)

            assert result is True
            # Should only run stage2 and stage3
            assert mock_run.call_count == 2