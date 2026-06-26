#!/usr/bin/env python3
import subprocess, sys
from datetime import datetime

PROFILES = ["minimal", "xfce", "gnome", "server", "audio-studio", "arm64"]
INIT_SYSTEMS = ["sysvinit", "systemd"]
OUTPUT_BASE = "/mnt/lfs-"

def build(profile, init):
    output = f"{OUTPUT_BASE}{profile}-{init}"
    cmd = ["sudo", "python3", "builder.py", "--profile", profile, "--init", init, "--output", output]
    print(f"🚀 Building {profile} with {init} – output: {output}")
    subprocess.run(cmd, check=True)

if __name__ == "__main__":
    for profile in PROFILES:
        for init in INIT_SYSTEMS:
            build(profile, init)