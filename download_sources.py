#!/usr/bin/env python3
"""
Téléchargement parallèle des sources LFS/BLFS
Usage: python3 download_sources.py [--parallel N] [--resume]
"""

import os
import sys
import subprocess
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

SOURCES_LIST = "packages/sources.list"
MD5SUMS = "packages/md5sums"
DEST_DIR = "lfs-output/sources"  # ou un répertoire personnalisé

def download_file(url, dest, resume=False):
    dest_path = Path(dest)
    if dest_path.exists() and resume:
        print(f"⏩ {dest_path.name} already exists, skipping")
        return True
    cmd = ["wget", "-c" if resume else "-q", "--show-progress", "-P", str(dest_path.parent), url]
    return subprocess.call(cmd) == 0

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--parallel", type=int, default=4, help="Number of parallel downloads")
    parser.add_argument("--resume", action="store_true", help="Resume interrupted downloads")
    args = parser.parse_args()

    Path(DEST_DIR).mkdir(parents=True, exist_ok=True)
    urls = []
    with open(SOURCES_LIST) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                urls.append(line)

    with ThreadPoolExecutor(max_workers=args.parallel) as executor:
        futures = {executor.submit(download_file, url, f"{DEST_DIR}/{url.split('/')[-1]}", args.resume): url for url in urls}
        for future in as_completed(futures):
            url = futures[future]
            if future.result():
                print(f"✅ {url}")
            else:
                print(f"❌ {url}")

if __name__ == "__main__":
    main()