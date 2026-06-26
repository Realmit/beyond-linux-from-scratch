#!/bin/bash
# BLFS base - Docker compatible minimal
set -e
LFS=${LFS:-/output/image}
echo "[INFO] BLFS base setup (Docker mode)"
mkdir -pv $LFS/usr/share/doc
mkdir -pv $LFS/etc/profile.d
echo "# BLFS base minimal" > $LFS/usr/share/doc/BLFS-README
echo "[SUCCESS] BLFS base complete"
exit 0
