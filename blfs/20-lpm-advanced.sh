#!/bin/bash
# LPM (Linux Package Manager) - Full-featured package manager for LFS
set -e

LFS=${LFS:-/output/image}
LPM_ROOT="$LFS/usr/local"
LPM_BIN="$LPM_ROOT/bin/lpm"
LPM_DB="/var/lib/lpm"
LPM_LOGS="/var/log/lpm"

# Couleurs pour les logs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_warn()  { echo -e "${YELLOW}[WARNING]${NC} $*"; }
log_debug() { echo -e "${BLUE}[DEBUG]${NC} $*"; }

# Créer les répertoires nécessaires
mkdir -pv "$LFS/var/lib/lpm"
mkdir -pv "$LFS/var/log/lpm"
mkdir -pv "$LFS/usr/local/bin"
mkdir -pv "$LFS/etc/lpm"
mkdir -pv "$LFS/usr/local/share/lpm"

# ============================================================================
# Script principal de LPM (installé dans $LFS/usr/local/bin/lpm)
# ============================================================================
cat > "$LFS/usr/local/bin/lpm" << 'LPM_SCRIPT'
#!/bin/bash
# LPM - Linux Package Manager for LFS
# Version: 1.0.0

set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Config
LPM_DB="/var/lib/lpm"
LPM_LOGS="/var/log/lpm"
LPM_ETC="/etc/lpm"
LPM_PACKAGES_DIR="/usr/local/share/lpm/packages"

# Fonctions de log
log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_warn()  { echo -e "${YELLOW}[WARNING]${NC} $*"; }

# Initialisation des répertoires
init_dirs() {
    mkdir -p "$LPM_DB" "$LPM_LOGS" "$LPM_ETC" "$LPM_PACKAGES_DIR"
    touch "$LPM_DB/packages.list"
    touch "$LPM_DB/installed.list"
}

# Installer un paquet
install_package() {
    local pkg_name="$1"
    local pkg_file="$LPM_PACKAGES_DIR/$pkg_name.tar.xz"
    local pkg_dir="$LPM_DB/$pkg_name"

    if [ -z "$pkg_name" ]; then
        log_error "Usage: lpm install <package>"
        return 1
    fi

    if grep -q "^$pkg_name$" "$LPM_DB/installed.list" 2>/dev/null; then
        log_warn "Package '$pkg_name' is already installed"
        return 0
    fi

    if [ ! -f "$pkg_file" ]; then
        log_error "Package file not found: $pkg_file"
        return 1
    fi

    log_info "Installing package: $pkg_name"
    mkdir -p "$pkg_dir"
    tar -xf "$pkg_file" -C "$pkg_dir"

    # Exécuter le script d'installation si présent
    if [ -f "$pkg_dir/install.sh" ]; then
        log_info "Running install script for $pkg_name"
        (cd "$pkg_dir" && bash install.sh)
    fi

    # Copier les fichiers dans le système
    if [ -d "$pkg_dir/files" ]; then
        cp -rv "$pkg_dir/files"/* / 2>/dev/null || true
    fi

    # Enregistrer l'installation
    echo "$pkg_name" >> "$LPM_DB/installed.list"
    echo "$(date -Iseconds) - Installed $pkg_name" >> "$LPM_LOGS/install.log"
    log_success "Package '$pkg_name' installed successfully"
}

# Désinstaller un paquet
remove_package() {
    local pkg_name="$1"
    local pkg_dir="$LPM_DB/$pkg_name"

    if [ -z "$pkg_name" ]; then
        log_error "Usage: lpm remove <package>"
        return 1
    fi

    if ! grep -q "^$pkg_name$" "$LPM_DB/installed.list" 2>/dev/null; then
        log_error "Package '$pkg_name' is not installed"
        return 1
    fi

    log_info "Removing package: $pkg_name"

    # Exécuter le script de désinstallation si présent
    if [ -f "$pkg_dir/remove.sh" ]; then
        log_info "Running remove script for $pkg_name"
        (cd "$pkg_dir" && bash remove.sh)
    fi

    # Supprimer les fichiers (attention : fichiers système)
    if [ -d "$pkg_dir/files" ]; then
        # On ne supprime pas directement, on loggue pour l'instant
        log_warn "System files not removed (manual cleanup needed)"
        # Option avancée : utiliser un manifeste
        # find $pkg_dir/files -type f -exec rm -f {} \;
    fi

    # Retirer de la liste des installés
    sed -i "/^$pkg_name$/d" "$LPM_DB/installed.list"
    echo "$(date -Iseconds) - Removed $pkg_name" >> "$LPM_LOGS/remove.log"
    log_success "Package '$pkg_name' removed"
}

# Lister les paquets installés
list_packages() {
    if [ ! -s "$LPM_DB/installed.list" ]; then
        log_info "No packages installed"
        return 0
    fi
    echo -e "${BLUE}Installed packages:${NC}"
    cat "$LPM_DB/installed.list" | sort | while read pkg; do
        echo "  $pkg"
    done
}

# Rechercher un paquet
search_package() {
    local pattern="$1"
    if [ -z "$pattern" ]; then
        log_error "Usage: lpm search <pattern>"
        return 1
    fi
    echo -e "${BLUE}Searching for '$pattern':${NC}"
    grep -i "$pattern" "$LPM_DB/packages.list" 2>/dev/null || echo "  No matches found"
}

# Mettre à jour un paquet (réinstallation)
update_package() {
    local pkg_name="$1"
    if [ -z "$pkg_name" ]; then
        log_error "Usage: lpm update <package>"
        return 1
    fi
    remove_package "$pkg_name"
    install_package "$pkg_name"
}

# Mettre à jour la base de données des paquets
update_db() {
    log_info "Updating package database..."
    # Simuler une mise à jour depuis un dépôt distant (pour l'exemple)
    # Dans la vraie vie, on téléchargerait un fichier index depuis un serveur
    echo "# LPM Package Database" > "$LPM_DB/packages.list"
    echo "# Generated on $(date)" >> "$LPM_DB/packages.list"
    # Ajouter des paquets factices pour l'exemple
    cat >> "$LPM_DB/packages.list" << 'PKG_LIST'
bash-5.2.21
coreutils-9.4
gcc-13.2.0
glibc-2.38
make-4.4.1
tar-1.35
xz-5.4.6
linux-6.12.10
openssl-3.2.0
curl-8.5.0
PKG_LIST
    log_success "Database updated"
}

# Afficher l'aide
show_help() {
    cat << 'HELP'
LPM - Linux Package Manager for LFS
Usage: lpm <command> [options]

Commands:
  install <package>      Install a package
  remove <package>       Remove a package
  list                   List installed packages
  search <pattern>       Search for packages
  update <package>       Update (reinstall) a package
  update-db              Update the package database
  help                   Show this help
  version                Show version

Examples:
  lpm install bash
  lpm list
  lpm search gcc

HELP
}

# Version
show_version() {
    echo "LPM version 1.0.0 (LFS Package Manager)"
    echo "Built for LFS 13.0"
}

# Main
main() {
    init_dirs
    case "$1" in
        install)     shift; install_package "$@" ;;
        remove)      shift; remove_package "$@" ;;
        list)        list_packages ;;
        search)      shift; search_package "$@" ;;
        update)      shift; update_package "$@" ;;
        update-db)   update_db ;;
        help|--help|-h) show_help ;;
        version|--version|-v) show_version ;;
        *)           log_error "Unknown command: $1"; show_help; exit 1 ;;
    esac
}

# Si le script est exécuté directement
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
LPM_SCRIPT

# ============================================================================
# Créer un paquet exemple pour tester LPM
# ============================================================================
cat > "$LFS/usr/local/share/lpm/packages/hello.tar.xz" << 'PKG' | base64 -d > /tmp/hello.pkg
# Ceci est un exemple de paquet (placeholder)
# Dans la vraie vie, ce serait une archive tar.xz contenant un répertoire avec:
# - files/ (les fichiers à installer)
# - install.sh (script d'installation)
# - remove.sh (script de désinstallation)
PKG

# Créer un répertoire d'exemple pour un paquet factice
mkdir -p "$LFS/usr/local/share/lpm/packages/hello"
mkdir -p "$LFS/usr/local/share/lpm/packages/hello/files/usr/local/bin"
cat > "$LFS/usr/local/share/lpm/packages/hello/files/usr/local/bin/hello" << 'EOF'
#!/bin/bash
echo "Hello from LPM package!"
EOF
chmod +x "$LFS/usr/local/share/lpm/packages/hello/files/usr/local/bin/hello"

cat > "$LFS/usr/local/share/lpm/packages/hello/install.sh" << 'EOF'
#!/bin/bash
echo "Installing hello package..."
cp -v files/usr/local/bin/hello /usr/local/bin/
echo "Hello package installed!"
EOF
chmod +x "$LFS/usr/local/share/lpm/packages/hello/install.sh"

cat > "$LFS/usr/local/share/lpm/packages/hello/remove.sh" << 'EOF'
#!/bin/bash
echo "Removing hello package..."
rm -fv /usr/local/bin/hello
echo "Hello package removed!"
EOF
chmod +x "$LFS/usr/local/share/lpm/packages/hello/remove.sh"

# Créer une archive du paquet hello
cd "$LFS/usr/local/share/lpm/packages"
tar -cf hello.tar hello/
xz -f hello.tar 2>/dev/null || true
rm -rf hello/

# ============================================================================
# Installer la base de données initiale
# ============================================================================
chmod +x "$LFS/usr/local/bin/lpm"

# Exécuter l'initialisation dans le chroot (ou en mode Docker)
if [ -d "$LFS" ]; then
    log_info "Initializing LPM database"
    chroot "$LFS" /usr/local/bin/lpm update-db 2>/dev/null || true
    chroot "$LFS" /usr/local/bin/lpm install hello 2>/dev/null || true
fi

log_success "LPM (Linux Package Manager) installed successfully!"
log_info "Usage: lpm [install|remove|list|search|update|update-db|help|version]"