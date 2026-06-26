#!/usr/bin/env python3
import shutil, sys

REQUIRED = ["bash", "gcc", "make", "bison", "flex", "gawk", "m4", "wget", "tar", "gzip", "xorriso", "parted", "rsync", "bc", "cpio", "kmod", "openssl"]

missing = []
for cmd in REQUIRED:
    if not shutil.which(cmd):
        missing.append(cmd)
if missing:
    print("❌ Missing commands:", ", ".join(missing))
    sys.exit(1)
else:
    print("✅ All required commands found")