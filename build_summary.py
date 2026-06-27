#!/usr/bin/env python3
"""
Rapport de build LFS
Usage: python3 build_summary.py [build_info.json]
"""

import json
import sys
from pathlib import Path
from datetime import datetime

def main():
    json_file = sys.argv[1] if len(sys.argv) > 1 else "lfs-output/build_info.json"
    if not Path(json_file).exists():
        print("build_info.json not found")
        sys.exit(1)

    with open(json_file) as f:
        data = json.load(f)

    print("=" * 60)
    print(f"LFS Build Summary – {data.get('build_date', 'unknown')}")
    print("=" * 60)
    print(f"Profile        : {data.get('profile', 'N/A')}")
    print(f"Init System    : {data.get('init_system', 'N/A')}")
    print(f"Architecture   : {data.get('architecture', 'N/A')}")
    print(f"Live System    : {data.get('features', {}).get('live_system', False)}")
    print(f"Security       : {data.get('features', {}).get('security', False)}")
    print(f"Build time     : {data.get('build_duration', 'N/A')}")
    print(f"ISO size       : {data.get('iso_size_mb', 'N/A')} MB")
    print("=" * 60)

if __name__ == "__main__":
    main()