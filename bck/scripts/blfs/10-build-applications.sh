#!/bin/bash
# Applications - Docker compatible minimal
set -e
LFS=${LFS:-/output/image}
echo "[INFO] Setting up applications (Docker mode)"
mkdir -pv $LFS/usr/share/applications
echo "# Minimal applications" > $LFS/usr/share/applications/README
echo "[SUCCESS] Applications skeleton created"
exit 0
