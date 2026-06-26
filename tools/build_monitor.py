#!/usr/bin/env python3
import time, sys
from pathlib import Path

LOG_FILE = "lfs-output/logs/build.log"

def monitor():
    if not Path(LOG_FILE).exists():
        print("⚠️ Build log not found yet, waiting...")
    with open(LOG_FILE, "r") as f:
        f.seek(0, 2)
        while True:
            line = f.readline()
            if not line:
                time.sleep(0.5)
                continue
            if "ERROR" in line:
                print(f"\033[91m{line.strip()}\033[0m")
            elif "WARNING" in line:
                print(f"\033[93m{line.strip()}\033[0m")
            elif "SUCCESS" in line:
                print(f"\033[92m{line.strip()}\033[0m")
            else:
                print(line.strip())

if __name__ == "__main__":
    try:
        monitor()
    except KeyboardInterrupt:
        print("\nMonitoring stopped.")