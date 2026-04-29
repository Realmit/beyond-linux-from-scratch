#!/bin/bash
# tools/build-matrix.sh

ARCHITECTURES=("x86_64" "aarch64" "armv7l" "riscv64")
PROFILES=("minimal" "xfce" "secure")

for arch in "${ARCHITECTURES[@]}"; do
    for profile in "${PROFILES[@]}"; do
        echo "Building $profile for $arch"

        export LFS_TGT="${arch}-lfs-linux-gnu"

        python3 builder.py \
            --profile "$profile" \
            --output "./lfs-${arch}-${profile}" \
            --config "config/build-${arch}.conf"
    done
done