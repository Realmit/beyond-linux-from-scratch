#!/usr/bin/env python3
"""
Création d'une partition de persistance sur une clé USB live
Usage: sudo python3 create_persistence.py /dev/sdb [size_in_MB]
"""

import sys
import subprocess
import argparse

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("device", help="USB device (e.g., /dev/sdb)")
    parser.add_argument("size", type=int, default=4096, help="Size in MB")
    args = parser.parse_args()

    if not args.device.startswith("/dev/"):
        print(" Invalid device")
        sys.exit(1)

    # Créer la partition
    subprocess.run(["sudo", "parted", "-s", args.device, "mkpart", "persistence", "ext4", "1MiB", f"{args.size}MiB"], check=True)
    subprocess.run(["sudo", "mkfs.ext4", "-F", "-L", "persistence", f"{args.device}1"], check=True)

    # Monter et créer persistence.conf
    subprocess.run(["sudo", "mount", f"{args.device}1", "/mnt"], check=True)
    with open("/mnt/persistence.conf", "w") as f:
        f.write("/ union\n")
    subprocess.run(["sudo", "umount", "/mnt"], check=True)
    print(f" Persistence partition créée sur {args.device}")

if __name__ == "__main__":
    main()