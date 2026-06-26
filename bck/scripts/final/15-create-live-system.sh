#!/bin/bash
set -e
LFS=${LFS:-/output/image}
mkdir -pv $LFS/live
echo "# Live system placeholder" > $LFS/live/README
exit 0
