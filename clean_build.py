#!/usr/bin/env python3
import shutil, argparse, subprocess
from pathlib import Path

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default="lfs-output")
    parser.add_argument("--docker", action="store_true")
    parser.add_argument("--sources", action="store_true")
    args = parser.parse_args()

    if args.output and Path(args.output).exists():
        shutil.rmtree(args.output)
        print(f"✅ Removed {args.output}")

    if args.docker:
        subprocess.run(["docker", "rmi", "lfs-builder-mac"], stderr=subprocess.DEVNULL)

    if args.sources:
        shutil.rmtree("lfs-output/sources", ignore_errors=True)
        print("✅ Source cache removed")

if __name__ == "__main__":
    main()