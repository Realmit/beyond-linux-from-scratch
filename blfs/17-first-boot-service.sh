#!/bin/bash
# First boot service - Docker compatible minimal
set -e
LFS=${LFS:-/output/image}
echo "[INFO] Setting up first-boot service (Docker mode)"
mkdir -pv $LFS/usr/local/sbin
mkdir -pv $LFS/etc/systemd/system 2>/dev/null || true
cat > $LFS/usr/local/sbin/first-boot.sh << 'SCRIPT'
#!/bin/bash
echo "First boot script executed"
exit 0
SCRIPT
chmod +x $LFS/usr/local/sbin/first-boot.sh
echo "# first-boot service placeholder" > $LFS/etc/systemd/system/first-boot.service 2>/dev/null || true
echo "[SUCCESS] First-boot service skeleton created"
exit 0
