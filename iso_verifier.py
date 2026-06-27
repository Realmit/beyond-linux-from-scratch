#!/usr/bin/env python3
import subprocess, sys
from pathlib import Path

def main():
    if len(sys.argv) < 2:
        print("Usage: iso_verifier.py <iso_file>")
        sys.exit(1)
    iso = sys.argv[1]
    if not Path(iso).exists():
        print("ISO not found")
        sys.exit(1)
    # SHA256
    print("📝 SHA256:", subprocess.check_output(["sha256sum", iso]).decode().split()[0])
    # Boot catalog check
    try:
        subprocess.run(["isoinfo", "-d", "-i", iso], check=True, capture_output=True)
        print("ISO appears bootable (isoinfo succeeded)")
    except:
        print("isoinfo failed – ISO may not be bootable")

if __name__ == "__main__":
    main()