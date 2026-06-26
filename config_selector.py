#!/usr/bin/env python3
import os, sys, shutil
from pathlib import Path

CONFIG_DIR = "config"
TARGET = "config/build.conf"

def list_configs():
    return [f for f in Path(CONFIG_DIR).iterdir() if f.suffix == ".conf" and f.name != "build.conf"]

def main():
    configs = list_configs()
    print("Available configuration files:")
    for i, cfg in enumerate(configs):
        print(f"{i+1}. {cfg.name}")
    choice = input("Select number (or 0 to cancel): ")
    try:
        idx = int(choice) - 1
        if idx < 0:
            sys.exit()
        selected = configs[idx]
        shutil.copy2(selected, TARGET)
        print(f"✅ {selected.name} copied to {TARGET}")
    except:
        print("Invalid choice")

if __name__ == "__main__":
    main()