#!/usr/bin/env bash
# make-release.sh – Crée une release du projet LFS/BLFS Builder
# Utilisation : ./make-release.sh [--no-tag] [--no-tar]

set -e

# ---------- Couleurs ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ---------- Aide ----------
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
  --no-tag       Ne pas créer le tag Git (seulement le tarball)
  --no-tar       Ne pas créer le tarball (seulement le tag)
  --help         Affiche cette aide

Description:
  Ce script prépare une release du projet :
    - Vérifie que le dépôt Git est propre
    - Extrait la version depuis builder.py
    - Demande confirmation
    - Crée un tarball du code source
    - Crée un tag Git (optionnel)
    - Affiche les instructions pour pousser et publier

La version est lue dans builder.py (__version__ = "X.Y.Z").
EOF
    exit 0
}

# ---------- Parse arguments ----------
CREATE_TAG=true
CREATE_TAR=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-tag)  CREATE_TAG=false ;;
        --no-tar)  CREATE_TAR=false ;;
        --help)    show_help ;;
        *)         echo -e "${RED}Option inconnue : $1${NC}"; show_help ;;
    esac
    shift
done

# ---------- Vérifications ----------
# Être dans le répertoire du script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Vérifier que c'est un dépôt Git
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo -e "${RED}Erreur : ce répertoire n'est pas un dépôt Git.${NC}"
    exit 1
fi

# Vérifier qu'il n'y a pas de modifications non commitées
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo -e "${YELLOW}Attention : il y a des modifications non commitées.${NC}"
    read -p "Voulez-vous les commiter maintenant ? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Commit en cours...${NC}"
        git add -A
        git commit -m "WIP avant release"
    else
        echo -e "${RED}Abandon : les modifications doivent être commitées.${NC}"
        exit 1
    fi
fi

# Vérifier qu'il n'y a pas de tags en attente de push ? On ne bloque pas.

# ---------- Extraire la version depuis builder.py ----------
VERSION_FILE="builder.py"
if [ ! -f "$VERSION_FILE" ]; then
    echo -e "${RED}Erreur : $VERSION_FILE introuvable.${NC}"
    exit 1
fi

VERSION=$(grep -E '^__version__\s*=\s*"[0-9]+\.[0-9]+\.[0-9]+"' "$VERSION_FILE" | sed -E 's/.*"([0-9]+\.[0-9]+\.[0-9]+)".*/\1/')
if [ -z "$VERSION" ]; then
    echo -e "${RED}Erreur : impossible d'extraire la version depuis $VERSION_FILE.${NC}"
    echo "Recherchez une ligne comme : __version__ = \"X.Y.Z\""
    exit 1
fi

echo -e "${GREEN}Version détectée : ${VERSION}${NC}"

# ---------- Vérifier que le tag n'existe pas déjà ----------
if git rev-parse "v$VERSION" >/dev/null 2>&1; then
    echo -e "${YELLOW}Le tag v$VERSION existe déjà.${NC}"
    read -p "Voulez-vous le supprimer et le recréer ? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git tag -d "v$VERSION"
        echo -e "${GREEN}Tag supprimé.${NC}"
    else
        echo -e "${RED}Abandon.${NC}"
        exit 1
    fi
fi

# ---------- Résumé et confirmation ----------
echo -e "${BLUE}Préparation de la release v${VERSION}${NC}"
echo "  - Créer un tag ?     : $([ "$CREATE_TAG" = true ] && echo "OUI" || echo "NON")"
echo "  - Créer un tarball ? : $([ "$CREATE_TAR" = true ] && echo "OUI" || echo "NON")"
echo

read -p "Continuer ? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}Abandon.${NC}"
    exit 1
fi

# ---------- Créer le tarball ----------
if [ "$CREATE_TAR" = true ]; then
    TAR_NAME="lfs-builder-${VERSION}.tar.gz"
    EXCLUDE=(
        --exclude='.git'
        --exclude='__pycache__'
        --exclude='*.pyc'
        --exclude='.pytest_cache'
        --exclude='.coverage'
        --exclude='htmlcov'
        --exclude='coverage.xml'
        --exclude='*.egg-info'
        --exclude='.venv'
        --exclude='venv'
        --exclude='env'
        --exclude='lfs-build'
        --exclude='*.iso'
        --exclude='*.img'
        --exclude='*.qcow2'
        --exclude='.DS_Store'
    )
    echo -e "${BLUE}Création du tarball $TAR_NAME...${NC}"
    tar -czf "$TAR_NAME" "${EXCLUDE[@]}" .
    echo -e "${GREEN}Tarball créé : $TAR_NAME${NC}"
fi

# ---------- Créer le tag ----------
if [ "$CREATE_TAG" = true ]; then
    echo -e "${BLUE}Création du tag v$VERSION...${NC}"
    git tag -a "v$VERSION" -m "Release v$VERSION"
    echo -e "${GREEN}Tag créé.${NC}"
fi

# ---------- Instructions ----------
echo
echo -e "${GREEN}=== Release v$VERSION préparée avec succès ! ===${NC}"
echo
echo "Prochaines étapes :"
if [ "$CREATE_TAG" = true ]; then
    echo "  1. Pousser le tag :"
    echo "     git push origin v$VERSION"
fi
if [ "$CREATE_TAR" = true ]; then
    echo "  2. Publier le tarball :"
    echo "     - Créer une release sur GitHub avec le tag v$VERSION"
    echo "     - Uploader $TAR_NAME comme asset"
    echo "  3. (Optionnel) Vérifier le contenu du tarball :"
    echo "     tar -tzf $TAR_NAME | head -20"
fi
echo
echo "Pour créer une release GitHub en ligne de commande :"
echo "  gh release create v$VERSION $TAR_NAME --title \"LFS Builder v$VERSION\" --notes \"Release notes...\""
echo
echo -e "${BLUE}Bonne release !${NC}"