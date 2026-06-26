#!/usr/bin/env python3
import shutil, argparse
from pathlib import Path

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--lfs", required=True, help="LFS mount point")
    args = parser.parse_args()
    lfs = Path(args.lfs)
    shutil.copy2("logo.svg", lfs / "usr/share/pixmaps/logo.svg")
    shutil.copy2("lfs-wallpaper.png", lfs / "usr/share/backgrounds/lfs-wallpaper.png")
    shutil.copytree("branding", lfs / "usr/share/themes/LFS", dirs_exist_ok=True)
    print("✅ Branding applied")

if __name__ == "__main__":
    main()