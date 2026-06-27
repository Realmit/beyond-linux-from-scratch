#!/usr/bin/env python3
"""
Création d’un ISO bootable depuis le système LFS
Usage: python3 make_iso.py --lfs /mnt/lfs --output lfs.iso
"""

import argparse
import subprocess
import os
from pathlib import Path

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--lfs", required=True, help="Mount point of LFS system")
    parser.add_argument("--output", default="lfs-installer.iso", help="Output ISO file")
    args = parser.parse_args()

    lfs = Path(args.lfs)
    if not lfs.exists():
        print("LFS directory does not exist")
        sys.exit(1)

    # Vérifier que grub-mkrescue est disponible
    if not shutil.which("grub-mkrescue"):
        print("grub-mkrescue not found. Install grub-common or grub2-tools.")
        sys.exit(1)

    # Créer un répertoire temporaire pour le contenu de l'ISO
    iso_root = Path("/tmp/lfs-iso")
    iso_root.mkdir(exist_ok=True)

    # Copier le système (exclure /dev, /proc, etc.)
    subprocess.run(["rsync", "-a", "--exclude=/dev", "--exclude=/proc", "--exclude=/sys",
                    "--exclude=/tmp", "--exclude=/run", "--exclude=/mnt",
                    f"{lfs}/", f"{iso_root}/"], check=True)

    # Générer l'ISO
    cmd = ["grub-mkrescue", "-o", args.output, str(iso_root)]
    subprocess.run(cmd, check=True)

    # Nettoyer
    import shutil
    shutil.rmtree(iso_root)
    print(f"✅ ISO créé : {args.output}")

if __name__ == "__main__":
    import shutil
    main()