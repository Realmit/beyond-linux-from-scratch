#!/bin/bash
# LFS Package Manager - Interface utilisateur

LPM_DB="/var/lib/lpm/db.json"
LPM_REPOS="/etc/lpm/repos.d/"

case "$1" in
    search)
        echo "🔍 Recherche de paquets: $2"
        find /var/lib/lpm/packages -name "*$2*" -exec basename {} .json \;
        ;;
    info)
        echo "📦 Informations sur $2:"
        cat "/var/lib/lpm/packages/$2.json" | jq '.description, .version, .size, .dependencies'
        ;;
    depends)
        echo "📊 Arbre des dépendances pour $2:"
        lpm show-dep-tree "$2"
        ;;
    autoremove)
        echo "🧹 Suppression des paquets orphelins..."
        lpm find-orphans | xargs lpm remove
        ;;
    upgrade-all)
        echo "🔄 Mise à jour de tous les paquets..."
        for pkg in $(lpm list-installed); do
            lpm upgrade "$pkg"
        done
        ;;
    backup)
        echo "💾 Sauvegarde de la liste des paquets..."
        lpm list-installed > "/home/$USER/lpm-backup-$(date +%Y%m%d).txt"
        ;;
    restore-backup)
        echo "📀 Restauration depuis sauvegarde..."
        cat "$2" | while read pkg; do
            lpm install "$pkg"
        done
        ;;
    *)
        echo "LFS Package Manager v1.0"
        echo "Usage: lpm {install|remove|search|info|depends|upgrade|autoremove|backup|restore-backup}"
        ;;
esac