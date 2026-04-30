# ARM64 LFS Profile

This profile builds LFS Linux for ARM64 architectures (aarch64).

## Supported Boards

| Board | Status | U-Boot Config | Kernel DTB |
|-------|--------|---------------|------------|
| Raspberry Pi 4 | ✅ Full | rpi_4 | bcm2711-rpi-4-b.dtb |
| Raspberry Pi 5 | ✅ Full | rpi_5 | bcm2712-rpi-5-b.dtb |
| Orange Pi PC | 🧪 Testing | orangepi_pc | sun8i-h3-orangepi-pc.dtb |
| Pine64 | 🧪 Testing | pine64_plus | sun50i-a64-pine64-plus.dtb |
| Generic ARM64 | ⚠️ Basic | generic | generic-arm64.dtb |

## Build Command

```bash
# Build for Raspberry Pi 4
BOARD=rpi_4 python3 builder.py --profile arm64 --config config/build-cross.conf

# Build for Orange Pi
BOARD=orangepi_pc python3 builder.py --profile arm64 --config config/build-cross.conf

# Build with SD card image creation
CREATE_SD_IMAGE=yes python3 builder.py --profile arm64 --config config/build-cross.conf

# Flash to SD card
dd if=lfs-arm64.img of=/dev/sdb bs=4M status=progress

# Or write individual partitions
mkfs.vfat /dev/sdb1
mkfs.ext4 /dev/sdb2
# Copy boot and root files