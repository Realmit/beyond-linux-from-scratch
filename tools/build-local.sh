#!/bin/bash
# Build with XFCE + sysvinit, live ISO, using local sources
python3 builder.py --profile xfce --init sysvinit --no-cache --output ./lfs-build