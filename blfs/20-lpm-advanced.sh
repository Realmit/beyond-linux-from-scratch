#!/bin/bash
# LPM advanced - full-featured package manager for LFS (Docker-aware)
set -e

LFS=${LFS:-/output/image}

# Define logging functions
log_info()    { echo "[INFO] $*"; }
log_error()   { echo "[ERROR] $*" >&2; }
log_success() { echo "[SUCCESS] $*"; }

# Create required directories
mkdir -pv "$LFS/var/lib/lpm"
mkdir -pv "$LFS/var/log/lpm"
mkdir -pv "$LFS/usr/local/bin"
mkdir -pv "$LFS/etc/lpm"
mkdir -pv "$LFS/usr/local/share/lpm"

# ---------------------------------------------------------------------------
# Main LPM script – full version
# ---------------------------------------------------------------------------
cat > "$LFS/usr/local/bin/lpm" << 'LPM_SCRIPT'
#!/bin/bash
# LPM - Linux Package Manager for LFS
# Version: 1.0.0

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

LPM_DB="/var/lib/lpm"
LPM_LOGS="/var/log/lpm"
LPM_ETC="/etc/lpm"
LPM_PACKAGES_DIR="/usr/local/share/lpm/packages"

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_warn()  { echo -e "${YELLOW}[WARNING]${NC} $*"; }
log_success(){ echo -e "${GREEN}[SUCCESS]${NC} $*"; }

init_dirs() {
    mkdir -p "$LPM_DB" "$LPM_LOGS" "$LPM_ETC" "$LPM_PACKAGES_DIR"
    touch "$LPM_DB/packages.list"
    touch "$LPM_DB/installed.list"
}

install_package() {
    local pkg_name="$1"
    local pkg_file="$LPM_PACKAGES_DIR/$pkg_name.tar.xz"
    local pkg_dir="$LPM_DB/$pkg_name"

    [ -z "$pkg_name" ] && { log_error "Usage: lpm install <package>"; return 1; }
    grep -q "^$pkg_name$" "$LPM_DB/installed.list" 2>/dev/null && { log_warn "Package '$pkg_name' already installed"; return 0; }
    [ ! -f "$pkg_file" ] && { log_error "Package file not found: $pkg_file"; return 1; }

    log_info "Installing package: $pkg_name"
    mkdir -p "$pkg_dir"
    tar -xf "$pkg_file" -C "$pkg_dir"

    if [ -f "$pkg_dir/install.sh" ]; then
        log_info "Running install script for $pkg_name"
        (cd "$pkg_dir" && bash install.sh)
    fi

    if [ -d "$pkg_dir/files" ]; then
        cp -rv "$pkg_dir/files"/* / 2>/dev/null || true
    fi

    echo "$pkg_name" >> "$LPM_DB/installed.list"
    echo "$(date -Iseconds) - Installed $pkg_name" >> "$LPM_LOGS/install.log"
    log_success "Package '$pkg_name' installed"
}

remove_package() {
    local pkg_name="$1"
    local pkg_dir="$LPM_DB/$pkg_name"

    [ -z "$pkg_name" ] && { log_error "Usage: lpm remove <package>"; return 1; }
    grep -q "^$pkg_name$" "$LPM_DB/installed.list" 2>/dev/null || { log_error "Package '$pkg_name' not installed"; return 1; }

    log_info "Removing package: $pkg_name"
    if [ -f "$pkg_dir/remove.sh" ]; then
        log_info "Running remove script"
        (cd "$pkg_dir" && bash remove.sh)
    fi

    if [ -d "$pkg_dir/files" ]; then
        log_warn "System files not automatically removed (manual cleanup may be needed)"
    fi

    sed -i "/^$pkg_name$/d" "$LPM_DB/installed.list"
    echo "$(date -Iseconds) - Removed $pkg_name" >> "$LPM_LOGS/remove.log"
    log_success "Package '$pkg_name' removed"
}

list_packages() {
    if [ ! -s "$LPM_DB/installed.list" ]; then
        log_info "No packages installed"
        return 0
    fi
    echo -e "${BLUE}Installed packages:${NC}"
    cat "$LPM_DB/installed.list" | sort | while read pkg; do echo "  $pkg"; done
}

search_package() {
    local pattern="$1"
    [ -z "$pattern" ] && { log_error "Usage: lpm search <pattern>"; return 1; }
    echo -e "${BLUE}Searching for '$pattern':${NC}"
    grep -i "$pattern" "$LPM_DB/packages.list" 2>/dev/null || echo "  No matches found"
}

update_package() {
    local pkg_name="$1"
    [ -z "$pkg_name" ] && { log_error "Usage: lpm update <package>"; return 1; }
    remove_package "$pkg_name"
    install_package "$pkg_name"
}

update_db() {
    log_info "Updating package database..."
    cat > "$LPM_DB/packages.list" << 'PKG_LIST'
# LPM Package Database
# Generated on $(date)
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

show_version() {
    echo "LPM version 1.0.0 (LFS Package Manager)"
    echo "Built for LFS 13.0"
}

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

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
LPM_SCRIPT

chmod +x "$LFS/usr/local/bin/lpm"

log_success "LPM (Linux Package Manager) installed successfully!"
log_info "Usage: lpm [install|remove|list|search|update|update-db|help|version]"