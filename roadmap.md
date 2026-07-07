# Roadmap: Full Configurability & Cross‑Distribution Support

## 1. Vision

Make the LFS/BLFS Builder **completely configurable** and able to run on **any major Linux distribution** (Ubuntu, Fedora, Arch, openSUSE, Gentoo, etc.), with full support for **different architectures** (x86_64, aarch64, riscv64, etc.) and **kernel types** (linux, linux-libre, gnu‑hurd, freebsd).  
All aspects – from dependency installation to build profiles – must be driven by configuration and environment detection, not hard‑coded assumptions.

---

## 2. Current State

| Area | Status |
|------|--------|
| **Builder Python code** | Mostly distribution‑agnostic; uses `platform.system()` and `shutil.which()`. However, some paths and command names (e.g., `apt` in `check_prerequisites`) are hard‑coded. |
| **Shell scripts** | Many scripts assume `bash` is at `/bin/bash`, use `sudo` unconditionally, and do not detect package managers or distribution‑specific tools. |
| **GitHub workflows** | Currently only run on `ubuntu-latest`. No matrix for other distros or architectures. |
| **Configuration** | Profile settings are static; some overrides exist (e.g., `--kernel-type`, `--init`), but not all options are exposed. |
| **Kernel type** | Supported in builder and scripts, but sources.list may not contain all kernel variants (e.g., linux-libre). |
| **Architecture** | Cross‑compilation is present but not fully integrated into all scripts (some still assume x86_64). |

---

## 3. Required Changes

### 3.1 Shell Scripts

| Script | Change Needed | Priority |
|--------|---------------|----------|
| All scripts | Replace hard‑coded `/bin/bash` with `#!/usr/bin/env bash` for portability. | High |
| `host/01-check-host.sh` | Detect distribution and install missing packages via the appropriate package manager (`apt`, `dnf`, `zypper`, `pacman`, `emerge`, etc.). Use a helper function. | High |
| `host/02-prepare-host.sh` | Use `useradd` flags that work on all distributions (e.g., `-m`, `-G`, `-s`). Avoid distribution‑specific options. | High |
| `host/04-build-toolchain.sh` | Detect if `gcc` is available; if not, install via distribution package manager. | Medium |
| `lfs/*.sh` and `blfs/*.sh` | Use environment variables for paths (already done). Check for existence of tools before using them. | Medium |
| `final/*.sh` | For ISO creation, check for `xorriso`, `grub-mkrescue`, etc. and provide fallbacks or clear error messages. | Medium |
| All scripts | Add a distribution detection function (`get_distro()`) to adapt paths (e.g., `/lib` vs `/usr/lib`, `/lib64` vs `/usr/lib64`). | Low |

### 3.2 Python Builder (`builder.py`)

| Component | Change Needed | Priority |
|-----------|---------------|----------|
| `check_prerequisites()` | Instead of hard‑coding `apt`, detect package manager and suggest install commands accordingly. | High |
| `_get_env()` | Pass distribution info as an environment variable to scripts (e.g., `DISTRO=ubuntu`). | Medium |
| `ProfileManager` | Allow profiles to define architecture‑specific settings (e.g., different packages for ARM64). | Medium |
| `LFSConfig` | Add a `platform` section to store detected distribution, version, and architecture. | Medium |
| `download_sources()` | Allow per‑kernel‑type source URLs; if `kernel.type` is `linux-libre`, use a different mirror. | High |
| `get_build_stages()` | Conditionally add steps based on architecture and kernel type (e.g., build U‑Boot only for ARM). | Medium |
| Error messages | Make them distribution‑agnostic and point to generic documentation. | Low |

### 3.3 GitHub Workflows (CI/CD)

| Workflow | Change Needed | Priority |
|----------|---------------|----------|
| `python-app.yml` | Test on multiple distributions (Ubuntu, Fedora, Arch) using containers or self‑hosted runners. | High |
| `XFCE SYSVINIT x86_64 Build Live ISO` | Add a matrix for distributions (ubuntu-latest, fedora-latest). | High |
| `Build ISO from Cache` | Add checks for distribution‑specific tools (e.g., `sudo` available). | Medium |
| All workflows | Use `actions/checkout@v4` and ensure all package installations use distribution‑specific commands. | Medium |
| Workflow triggers | Allow manual dispatch with parameters for distribution, architecture, kernel type. | Low |

### 3.4 Configuration Files

| File | Change Needed | Priority |
|------|---------------|----------|
| `config/build.conf` | Add a `distribution` section with default values for package manager, paths, etc. | High |
| `packages/sources.list` | Automatically include kernel‑type‑specific sources based on `kernel.type`. | High |
| `config/kernel-config` | Provide multiple kernel configs (e.g., `kernel-config-linux-libre`, `kernel-config-arm64`). | Medium |
| Profiles | Extend profile definitions to include architecture‑specific package lists and tool versions. | Medium |

### 3.5 Documentation

| Document | Change Needed | Priority |
|----------|---------------|----------|
| `README.md` | Update installation instructions for each supported distribution. | High |
| `ADVANCED.md` | Explain how to configure custom distribution, architecture, and kernel type. | Medium |
| `CONTRIBUTING.md` | Add guidelines for testing on multiple distributions. | Low |

---

## 4. Implementation Phases

### Phase 1: Core Configurability (Priority: High)
- Implement distribution detection in Python and shell scripts.
- Modify `host/01-check-host.sh` to install dependencies via detected package manager.
- Update `builder.py` to pass `DISTRO` to scripts.
- Add fallback mirrors for linux‑libre and other kernel types to `custom-sources.list`.
- Update `README.md` with per‑distribution installation instructions.

**Timeline:** 2 weeks

### Phase 2: Cross‑Architecture Support (Priority: Medium)
- Review all scripts for architecture assumptions (e.g., `arch/x86/boot/bzImage`).
- Ensure kernel build script (`09-build-kernel.sh`) uses `ARCH` and `CROSS_COMPILE` correctly.
- Test on ARM64 (using QEMU or real hardware) and adjust scripts.
- Add ARM64‑specific profiles and configurations.

**Timeline:** 3 weeks

### Phase 3: CI/CD Expansion (Priority: Medium)
- Extend GitHub workflows to test on Fedora, Arch, and openSUSE (using containers).
- Add matrix parameters for kernel types and architectures.
- Create a workflow that builds on multiple distributions and publishes artifacts.

**Timeline:** 2 weeks

### Phase 4: Profile and Configuration Overhaul (Priority: Low)
- Allow profiles to be fully overridden via command line and config files.
- Implement a profile inheritance system (e.g., `full` inherits from `gnome`).
- Add dynamic package selection based on architecture and kernel type.
- Provide a configuration wizard or interactive setup.

**Timeline:** 4 weeks

### Phase 5: Long‑Term Maintenance (Priority: Low)
- Create a regression test suite that runs on all supported distributions.
- Set up nightly builds on multiple architectures.
- Document all environment variables and configuration options.

**Timeline:** Ongoing

---

## 5. Key Dependencies & Risks

| Risk | Mitigation |
|------|------------|
| **Distribution differences in package names** | Maintain a mapping of common packages (e.g., `libssl-dev` vs `openssl-devel`). Use `pkg-config` fallbacks. |
| **Tool versions** | Use environment variables to specify tool versions; allow users to override. |
| **File system layout** | Use `$LFS` and relative paths; avoid hard‑coded `/usr/lib`. |
| **Kernel type availability** | Provide clear error messages and fallback URLs for missing tarballs. |
| **Test coverage** | Expand test suite with mock distributions (using Docker) to catch issues early. |

---

## 6. Success Criteria

- The builder can run on **Ubuntu, Fedora, Arch, openSUSE, and Gentoo** without manual intervention.
- Users can specify **any kernel type** (`linux`, `linux-libre`, etc.) and the builder downloads the correct sources.
- Profiles can be **customised** for any architecture (x86_64, aarch64) with appropriate packages and bootloader.
- GitHub Actions run on **multiple distributions** and report success/failure for each.
- **100% of scripts** use distribution‑agnostic commands and paths.

---

## 7. Next Steps

1. **Start Phase 1** by implementing distribution detection and dependency installation.
2. **Open issues** for each script that needs modification, assign priorities.
3. **Create a testing plan** for each distribution using Docker containers.
4. **Document progress** in this roadmap and update regularly.

---

**This roadmap ensures that the LFS/BLFS Builder becomes a truly universal tool, capable of running on any Linux distribution, building for any architecture, and using any kernel type – while remaining fully configurable and user‑friendly.**