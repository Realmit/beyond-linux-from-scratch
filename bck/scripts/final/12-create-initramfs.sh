#!/bin/bash
# Create initramfs

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/utils.sh"

log_info "Creating initramfs"

cat > $LFS/create-initramfs.sh << "EOF"
#!/bin/bash

set -e

# Create initramfs directory
mkdir -p /tmp/initramfs/{bin,dev,etc,lib,lib64,mnt,proc,root,sbin,sys,usr}
cd /tmp/initramfs

# Copy necessary binaries
cp /bin/busybox bin/
cp /sbin/blkid sbin/
cp /bin/mount bin/
cp /bin/umount bin/
cp /bin/sh bin/

# Copy libraries
ldd /bin/busybox | grep -o '/lib/[^ ]*' | xargs -I {} cp {} lib/
ldd /sbin/blkid | grep -o '/lib/[^ ]*' | xargs -I {} cp {} lib/

# Create device nodes
mknod -m 622 dev/console c 5 1
mknod -m 666 dev/null c 1 3
mknod -m 600 dev/mem c 1 1

# Create init script
cat > init << "INIT"
#!/bin/sh

# Mount essential filesystems
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev

# Detect root device
for dev in /dev/sd* /dev/nvme*; do
    if [ -b "$dev" ] && blkid "$dev" | grep -q "ext4"; then
        mount "$dev" /mnt
        break
    fi
done

# Cleanup and switch root
umount /proc
umount /sys
exec switch_root /mnt /sbin/init
INIT

chmod +x init

# Create initramfs image
find . | cpio -o -H newc | gzip > /boot/initramfs.img

rm -rf /tmp/initramfs

echo "Initramfs created successfully"
EOF

chmod +x $LFS/create-initramfs.sh

chroot "$LFS" /usr/bin/env -i \
    HOME=/root \
    TERM="$TERM" \
    PS1='(lfs chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin \
    /bin/bash /create-initramfs.sh

log_info "Initramfs creation complete!"