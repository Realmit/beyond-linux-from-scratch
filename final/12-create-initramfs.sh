#!/bin/bash
# Création d'un initramfs fonctionnel avec busybox (autodownload si absent)
set -e

LFS="${LFS:-/output/image}"
INITRAMFS_DIR="${LFS}/boot/initramfs-tmp"
INITRAMFS_OUTPUT="${LFS}/boot/initramfs.img"

echo "[INFO] Building initramfs for LFS..."

# Nettoyer les anciennes traces
rm -rf "$INITRAMFS_DIR"
mkdir -pv "$INITRAMFS_DIR"/{bin,dev,etc,lib,lib64,mnt,proc,root,sbin,sys,tmp,usr,var}

# --- Recherche de busybox ---
BUSYBOX_SRC=""
# 1. Chercher dans le rootfs
if [ -f "$LFS/bin/busybox" ]; then
    BUSYBOX_SRC="$LFS/bin/busybox"
elif [ -f "$LFS/usr/bin/busybox" ]; then
    BUSYBOX_SRC="$LFS/usr/bin/busybox"
elif [ -f "$LFS/sbin/busybox" ]; then
    BUSYBOX_SRC="$LFS/sbin/busybox"
fi

# 2. Si non trouvé, chercher sur l'hôte
if [ -z "$BUSYBOX_SRC" ] && command -v busybox >/dev/null 2>&1; then
    BUSYBOX_SRC="$(command -v busybox)"
    echo "[INFO] Using host busybox: $BUSYBOX_SRC"
fi

# 3. Si toujours pas, télécharger un binaire statique
if [ -z "$BUSYBOX_SRC" ]; then
    echo "[INFO] Busybox not found. Downloading static binary..."
    BUSYBOX_URL="https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox"
    wget -q -O /tmp/busybox "$BUSYBOX_URL"
    chmod +x /tmp/busybox
    BUSYBOX_SRC="/tmp/busybox"
    echo "[INFO] Downloaded busybox to $BUSYBOX_SRC"
fi

# Copier busybox dans l'initramfs
cp -a "$BUSYBOX_SRC" "$INITRAMFS_DIR/bin/busybox"
chmod 755 "$INITRAMFS_DIR/bin/busybox"

# Créer les liens symboliques pour toutes les commandes
cd "$INITRAMFS_DIR/bin"
for cmd in $(./busybox --list); do
    ln -sf busybox "$cmd"
done
cd - >/dev/null

# --- Créer les périphériques indispensables ---
# (nécessite sudo pour mknod)
if [ "$(whoami)" = "root" ]; then
    mknod -m 622 "$INITRAMFS_DIR/dev/console" c 5 1
    mknod -m 666 "$INITRAMFS_DIR/dev/null" c 1 3
    mknod -m 666 "$INITRAMFS_DIR/dev/zero" c 1 5
    mknod -m 666 "$INITRAMFS_DIR/dev/tty" c 5 0
else
    sudo mknod -m 622 "$INITRAMFS_DIR/dev/console" c 5 1
    sudo mknod -m 666 "$INITRAMFS_DIR/dev/null" c 1 3
    sudo mknod -m 666 "$INITRAMFS_DIR/dev/zero" c 1 5
    sudo mknod -m 666 "$INITRAMFS_DIR/dev/tty" c 5 0
fi

# --- Script init ---
cat > "$INITRAMFS_DIR/init" << 'EOF'
#!/bin/busybox sh
# Initramfs minimal – montage du rootfs réel

/bin/busybox mount -t proc proc /proc
/bin/busybox mount -t sysfs sysfs /sys
/bin/busybox mount -t devtmpfs devtmpfs /dev

# Chercher le vrai root (label=ROOT, UUID, ou /dev/sda2)
ROOT_DEV="/dev/sda2"  # À adapter
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

# --- Créer l'archive cpio compressée ---
cd "$INITRAMFS_DIR"
find . | cpio -o -H newc | gzip -9 > "$INITRAMFS_OUTPUT"
cd - >/dev/null

# Nettoyer
rm -rf "$INITRAMFS_DIR"

echo "[SUCCESS] Initramfs created at $INITRAMFS_OUTPUT"
ls -lh "$INITRAMFS_OUTPUT"