#!/bin/bash
# Create a functional initramfs with busybox (auto-download if missing)
set -e

# Re‑launch with sudo if not root (preserve environment)
if [ "$EUID" -ne 0 ]; then
    echo "[INFO] Relaunching with sudo..."
    exec sudo -E "$0" "$@"
fi

LFS="${LFS:-/output/image}"
INITRAMFS_DIR="${LFS}/boot/initramfs-tmp"
INITRAMFS_OUTPUT="${LFS}/boot/initramfs.img"

echo "[INFO] Building initramfs for LFS..."

rm -rf "$INITRAMFS_DIR"
mkdir -pv "$INITRAMFS_DIR"/{bin,dev,etc,lib,lib64,mnt,proc,root,sbin,sys,tmp,usr,var}

# --------------------------------------------------------------------------
# Find or download busybox
# --------------------------------------------------------------------------
BUSYBOX_SRC=""
if [ -f "$LFS/bin/busybox" ]; then
    BUSYBOX_SRC="$LFS/bin/busybox"
elif [ -f "$LFS/usr/bin/busybox" ]; then
    BUSYBOX_SRC="$LFS/usr/bin/busybox"
elif [ -f "$LFS/sbin/busybox" ]; then
    BUSYBOX_SRC="$LFS/sbin/busybox"
fi

if [ -z "$BUSYBOX_SRC" ] && command -v busybox >/dev/null 2>&1; then
    BUSYBOX_SRC="$(command -v busybox)"
    echo "[INFO] Using host busybox: $BUSYBOX_SRC"
fi

if [ -z "$BUSYBOX_SRC" ]; then
    echo "[INFO] Busybox not found. Downloading static binary..."
    BUSYBOX_URL="https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox"
    wget -q -O /tmp/busybox "$BUSYBOX_URL"
    chmod +x /tmp/busybox
    BUSYBOX_SRC="/tmp/busybox"
    echo "[INFO] Downloaded busybox to $BUSYBOX_SRC"
fi

cp -a "$BUSYBOX_SRC" "$INITRAMFS_DIR/bin/busybox"
chmod 755 "$INITRAMFS_DIR/bin/busybox"

# Create symlinks, ignoring 'busybox' itself
cd "$INITRAMFS_DIR/bin"
for cmd in $(./busybox --list); do
    if [ "$cmd" != "busybox" ]; then
        ln -sf busybox "$cmd"
    fi
done
cd - >/dev/null

# --------------------------------------------------------------------------
# Device nodes – try mknod; fall back to copying from host
# --------------------------------------------------------------------------
create_device() {
    local path="$1"
    local mode="$2"
    local major="$3"
    local minor="$4"
    if [ -e "$path" ]; then
        return 0
    fi
    if mknod -m "$mode" "$path" "$major" "$minor" 2>/dev/null; then
        return 0
    fi
    # Fallback: copy from host /dev if possible
    local devname="$(basename "$path")"
    if [ -e "/dev/$devname" ]; then
        cp -a "/dev/$devname" "$path"
        chmod "$mode" "$path"
        return 0
    fi
    echo "[WARNING] Could not create device node: $path"
    return 1
}

create_device "$INITRAMFS_DIR/dev/console" 622 c 5 1
create_device "$INITRAMFS_DIR/dev/null"    666 c 1 3
create_device "$INITRAMFS_DIR/dev/zero"    666 c 1 5
create_device "$INITRAMFS_DIR/dev/tty"     666 c 5 0

# --------------------------------------------------------------------------
# Init script
# --------------------------------------------------------------------------
cat > "$INITRAMFS_DIR/init" << 'EOF'
#!/bin/busybox sh
/bin/busybox mount -t proc proc /proc
/bin/busybox mount -t sysfs sysfs /sys
/bin/busybox mount -t devtmpfs devtmpfs /dev

ROOT_DEV="/dev/sda2"
if [ -b "$ROOT_DEV" ]; then
    /bin/busybox mount -t ext4 "$ROOT_DEV" /mnt
else
    echo "Root device $ROOT_DEV not found. Dropping to shell."
    /bin/busybox sh
fi

/bin/busybox umount /proc
/bin/busybox umount /sys
/bin/busybox umount /dev
exec /bin/busybox switch_root /mnt /sbin/init
EOF

chmod 755 "$INITRAMFS_DIR/init"

# --------------------------------------------------------------------------
# Create compressed cpio archive
# --------------------------------------------------------------------------
cd "$INITRAMFS_DIR"
find . | cpio -o -H newc | gzip -9 > "$INITRAMFS_OUTPUT"
cd - >/dev/null

rm -rf "$INITRAMFS_DIR"
echo "[SUCCESS] Initramfs created at $INITRAMFS_OUTPUT"
ls -lh "$INITRAMFS_OUTPUT"