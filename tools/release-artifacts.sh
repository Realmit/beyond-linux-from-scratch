#!/bin/bash
# Archive logs, config, and build_info.json
tar -czf build-debug-$(date +%Y%m%d).tar.gz lfs-build/logs/ lfs-build/build_info.json config/build.conf
echo "Debug archive created."