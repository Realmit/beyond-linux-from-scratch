# Contributing to LFS/BLFS Builder

First off, thank you for considering contributing to LFS/BLFS Builder! It's people like you that make this project better.

## Code of Conduct

This project and everyone participating in it is governed by our Code of Conduct. By participating, you are expected to uphold this code.

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check the issue tracker as you might find out that you don't need to create one. When you are creating a bug report, please include as many details as possible:

- **Use a clear and descriptive title**
- **Describe the exact steps to reproduce the problem**
- **Describe the behavior you observed and what you expected to see**
- **Include your environment** (OS, Python version, Docker version if used)
- **Include build logs** from `lfs-build/logs/`
- **Include your `build.conf`** (redact sensitive info)

Example bug report:
```markdown
## Description
[Clear description of the bug]

## Steps to Reproduce
1. Run `python3 builder.py --profile xfce`
2. Build fails at stage 'desktop'
3. Error: "xfce4-panel: command not found"

## Expected Behavior
Build should complete successfully

## Environment
- OS: Ubuntu 22.04
- Python: 3.10.12
- Builder version: 3.0.0
- Disk space: 120GB free

## Logs
[Attach relevant log files]