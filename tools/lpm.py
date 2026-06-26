#!/usr/bin/env python3
"""
LFS Package Manager (LPM) – version Python
Usage: ./lpm.py list | install <url> | remove <pkg> | search <keyword>
"""

import sys
import json
import urllib.request
import shutil
from pathlib import Path

DB_FILE = "/var/lib/lpm/db.json"
INSTALL_DIR = "/usr/local"

def load_db():
    if Path(DB_FILE).exists():
        with open(DB_FILE) as f:
            return json.load(f)
    return {"packages": []}

def save_db(db):
    Path(DB_FILE).parent.mkdir(parents=True, exist_ok=True)
    with open(DB_FILE, "w") as f:
        json.dump(db, f, indent=2)

def install(url):
    name = url.split("/")[-1]
    # Télécharger et extraire dans INSTALL_DIR (simplifié)
    print(f"Installing {name} from {url}")
    # Logique d'installation...
    db = load_db()
    db["packages"].append({"name": name, "url": url})
    save_db(db)

def list_packages():
    db = load_db()
    for pkg in db["packages"]:
        print(pkg["name"])

def main():
    if len(sys.argv) < 2:
        print("Usage: lpm list|install <url>|remove <pkg>|search <keyword>")
        sys.exit(1)
    cmd = sys.argv[1]
    if cmd == "list":
        list_packages()
    elif cmd == "install" and len(sys.argv) > 2:
        install(sys.argv[2])
    else:
        print("Command not implemented yet")

if __name__ == "__main__":
    main()