#!/bin/bash
# LFS Package Manager - User Interface

LPM_DB="/var/lib/lpm/db.json"
LPM_REPOS="/etc/lpm/repos.d/"

case "$1" in
    search)
        echo "Searching for packages: $2"
        find /var/lib/lpm/packages -name "*$2*" -exec basename {} .json \;
        ;;
    info)
        echo "Information about $2:"
        cat "/var/lib/lpm/packages/$2.json" | jq '.description, .version, .size, .dependencies'
        ;;
    depends)
        echo "Dependency tree for $2:"
        lpm show-dep-tree "$2"
        ;;
    autoremove)
        echo "Removing orphaned packages..."
        lpm find-orphans | xargs lpm remove
        ;;
    upgrade-all)
        echo "Updating all packages..."
        for pkg in $(lpm list-installed); do
            lpm upgrade "$pkg"
        done
        ;;
    backup)
        echo "Backing up package list..."
        lpm list-installed > "/home/$USER/lpm-backup-$(date +%Y%m%d).txt"
        ;;
    restore-backup)
        echo "Restoring from backup..."
        cat "$2" | while read pkg; do
            lpm install "$pkg"
        done
        ;;
    *)
        echo "LFS Package Manager v1.0"
        echo "Usage: lpm {install|remove|search|info|depends|upgrade|autoremove|backup|restore-backup}"
        ;;
esac