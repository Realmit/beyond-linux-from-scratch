#!/bin/bash
# Création d'un initramfs fonctionnel avec busybox
set -e

LFS="${LFS:-/output/image}"
INITRAMFS_DIR="${LFS}/boot/initramfs-tmp"
INITRAMFS_OUTPUT="${LFS}/boot/initramfs.img"

echo "[INFO] Building initramfs for LFS..."

# Nettoyer les anciennes traces
rm -rf "$INITRAMFS_DIR"
mkdir -pv "$INITRAMFS_DIR"/{bin,dev,etc,lib,lib64,mnt,proc,root,sbin,sys,tmp,usr,var}

# Copier busybox (si présent) ou un binaire statique
if [ -f "$LFS/bin/busybox" ]; then
    cp -a "$LFS/bin/busybox" "$INITRAMFS_DIR/bin/"
    # Créer les liens symboliques
    cd "$INITRAMFS_DIR/bin"
    for cmd in $(./busybox --list); do
        ln -sf busybox "$cmd"
    done
    cd - >/dev/null
else
    echo "[ERROR] busybox not found in $LFS/bin. Please install busybox."
    exit 1
fi

# Créer les périphériques indispensables
sudo mknod -m 622 "$INITRAMFS_DIR/dev/console" c 5 1
sudo mknod -m 666 "$INITRAMFS_DIR/dev/null" c 1 3
sudo mknod -m 666 "$INITRAMFS_DIR/dev/zero" c 1 5
sudo mknod -m 666 "$INITRAMFS_DIR/dev/tty" c 5 0

# Script init
cat > "$INITRAMFS_DIR/init" << 'EOF'
#!/bin/busybox sh
# Initramfs minimal – montage du rootfs réel

/bin/busybox mount -t proc proc /proc
/bin/busybox mount -t sysfs sysfs /sys
/bin/busybox mount -t devtmpfs devtmpfs /dev

# Chercher le vrai root (ex: label=ROOT, UUID, ou /dev/sda2)
ROOT_DEV="/dev/sda2"  # À adapter
if [ -b "$ROOT_DEV" ]; then
    /bin/busybox mount -t ext4 "$ROOT_DEV" /mnt
else
    echo "Root device $ROOT_DEV not found. Dropping to shell."
    /bin/busybox sh
fi

# Nettoyer et passer au vrai root
/bin/busybox umount /proc
/bin/busybox umount /sys
/bin/busybox umount /dev
exec /bin/busybox switch_root /mnt /sbin/init
EOF

chmod 755 "$INITRAMFS_DIR/init"

# Créer l'archive cpio compressée
cd "$INITRAMFS_DIR"
find . | cpio -o -H newc | gzip -9 > "$INITRAMFS_OUTPUT"
cd - >/dev/null

# Nettoyer les fichiers temporaires
rm -rf "$INITRAMFS_DIR"

echo "[SUCCESS] Initramfs created at $INITRAMFS_OUTPUT"
ls -lh "$INITRAMFS_OUTPUT"