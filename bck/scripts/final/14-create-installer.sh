#!/bin/bash
set -e
LFS=${LFS:-/output/image}
touch $LFS/lfs-installer.iso
echo "Installer ISO placeholder" > $LFS/lfs-installer.iso
exit 0
