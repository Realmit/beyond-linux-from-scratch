# Resuming Build from a Failed Stage

The LFS/BLFS build process consists of many stages, and a full build can take several hours. If a stage fails, you don’t need to start from scratch – you can **resume** from the stage that failed.

---

## Why Resume?

- **Save time** – Skip stages that already completed successfully.
- **Debug efficiently** – Fix the issue and retry only the failing stage.
- **Avoid re‑downloading** – Sources already downloaded are reused.

---

## How It Works

The builder tracks the build stages listed in `BUILD_STAGES` (see the full list below).  
When you pass the `--resume-from <stage>` option, the builder will **skip all stages before** the specified stage and start executing from that stage onwards.

---

## Identifying the Correct Stage Name

The stage name is the **first element** of each tuple in the `BUILD_STAGES` list. It is **case‑sensitive**.

### Full List of Stage Names

| Stage Name | Script Path |
|------------|-------------|
| `host-check` | `host/01-check-host.sh` |
| `host-prepare` | `host/02-prepare-host.sh` |
| `disk-image` | `host/03-create-disk-image.sh` |
| `toolchain` | `host/04-build-toolchain.sh` |
| `qemu-setup` *(optional)* | `host/00-setup-qemu.sh` |
| `uboot` *(optional)* | `host/05-build-uboot.sh` |
| `lfs-basic` | `lfs/05-build-lfs-basic.sh` |
| `lfs-system` | `lfs/06-build-lfs-system.sh` |
| `init-system` | `lfs/06a-init-system.sh` |
| `service-mgmt` | `lfs/06b-service-management.sh` |
| `configure-lfs` | `lfs/07-configure-lfs.sh` |
| `blfs-base` | `lfs/08-build-blfs-base.sh` |
| `desktop` | `blfs/09-build-desktop.sh` |
| `applications` | `blfs/10-build-applications.sh` |
| `configure-desktop` | `blfs/11-configure-desktop.sh` |
| `java-dev` *(if enabled)* | `blfs/12-install-java-dev.sh` |
| `package-manager` | `blfs/13-create-package-manager.sh` |
| `base-packages` | `blfs/14-create-base-packages.sh` |
| `security` *(if enabled)* | `blfs/15-security-hardening.sh` |
| `privacy` *(if enabled)* | `blfs/16-privacy-tools.sh` |
| `branding` | `blfs/21-branding.sh` |
| `first-boot` | `blfs/17-first-boot-service.sh` |
| `system-updater` | `blfs/18-system-updater.sh` |
| `package-updater` | `blfs/19-package-updater.sh` |
| `lpm-advanced` | `blfs/20-lpm-advanced.sh` |
| `initramfs` | `final/12-create-initramfs.sh` |
| `bootloader` | `final/13-create-bootloader.sh` |
| `installer` | `final/14-create-installer.sh` |
| `live-system` | `final/15-create-live-system.sh` |

> **Note**: Optional stages (like `qemu-setup`, `uboot`, `java-dev`, `security`, `privacy`) are only included if your profile enables them.

---

## How to Find the Failing Stage

When a build fails, the last few lines of the log will show something like:

```
[10/24] Processing stage: desktop
...
ERROR - Build failed at stage: desktop
INFO - You can resume with: --resume-from desktop
```

Alternatively, check the logs in `lfs-output/logs/`. The log file for each stage is named `<stage-name>.log`.

---

## Resuming from a Stage

Simply pass the `--resume-from` option to the `builder.py` script, using the exact stage name.

### Syntax

```bash
python3 builder.py --resume-from <stage-name> [other options]
```

### Examples

#### Resume from `desktop` (after fixing a desktop-related issue)

```bash
python3 builder.py --resume-from desktop --profile xfce --output /mnt/lfs
```

#### Resume from `init-system` (if the init system installation failed)

```bash
python3 builder.py --resume-from init-system --profile minimal --init sysvinit
```

#### Resume from `installer` (if ISO creation failed)

```bash
python3 builder.py --resume-from installer --output ./lfs-build
```

---

## Important Notes

- **Configuration consistency** – Use the same profile, init system, and output directory as the original build.
- **Sources** – If some sources failed to download, the resume will continue downloading missing files (the download stage is skipped if you resume after it, but the builder will still download sources as needed when scripts require them).
- **Environment** – The environment variables (like `LFS`, `INIT_SYSTEM`, etc.) are set again, so you don’t need to re‑export them.
- **Docker** – If you are using the Docker builder (macOS), use the same Docker command with `--resume-from`.

### Example with Docker

```bash
docker run --rm -it --privileged \
  -v "$(pwd):/lfs-builder" \
  -v "$(pwd)/lfs-output:/output" \
  -w /lfs-builder \
  lfs-builder-mac:latest \
  python3 builder.py --resume-from desktop --profile xfce --output /output
```

---

## Tips for Successful Resume

1. **Check the logs** – Always inspect the log of the failing stage to understand the root cause.
2. **Fix the issue** – This may involve editing a script, installing a missing dependency, or adjusting configuration.
3. **Clean partial outputs** – If the failure left incomplete files, you may need to manually remove them (e.g., `rm -rf /mnt/lfs/sources/partial-file`).
4. **Use `--verbose`** – For more detailed output during the resume, add `--verbose` to see exactly what’s happening.

```bash
python3 builder.py --resume-from package-manager --verbose
```

---

## Common Scenarios

| Failure Stage | Typical Cause | Action |
|---------------|---------------|--------|
| `host-check` | Missing host tools | Install missing packages (`build-essential`, etc.) |
| `toolchain` | GCC or binutils build failure | Check log, fix environment, resume from `toolchain` |
| `lfs-basic` | Source extraction issue | Verify sources, resume from `lfs-basic` |
| `desktop` | XFCE build error | Install missing dependencies, resume from `desktop` |
| `installer` | `grub-mkrescue` not found | Install `grub-common`, resume from `installer` |

---

## Resuming from a Stage Not in the List

The `--resume-from` argument must match one of the stage names listed above. If you provide an unknown name, the builder will start from the beginning (since it doesn't find the stage). Check the stage name carefully.

---

## Conclusion

The `--resume-from` option is a powerful tool that saves time and effort during the build process. Use it whenever a stage fails to avoid rebuilding everything from scratch.

For more details, see the [Advanced Usage Guide](ADVANCED.md).