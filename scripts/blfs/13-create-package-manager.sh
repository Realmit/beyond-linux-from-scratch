#!/bin/bash
# Package Manager for LFS - "lpm" (LFS Package Manager)
# Run inside chroot environment

set -e

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[0;34m[SUCCESS]\033[0m $1"; }

LPM_VERSION="1.0.0"
LPM_ROOT="/var/lib/lpm"
LPM_DB="${LPM_ROOT}/packages.db"
LPM_REPOS="${LPM_ROOT}/repos"
LPM_LOGS="${LPM_ROOT}/logs"

# Create directory structure
mkdir -p ${LPM_ROOT} ${LPM_REPOS} ${LPM_LOGS}
mkdir -p /etc/lpm/repos.d
mkdir -p /var/cache/lpm/packages

###############################################################################
# CORE PACKAGE MANAGER SCRIPT
###############################################################################

cat > /usr/bin/lpm << 'EOF'
#!/bin/bash
# LPM - LFS Package Manager
# Version: 1.0.0

set -e

LPM_ROOT="/var/lib/lpm"
LPM_DB="${LPM_ROOT}/packages.db"
LPM_REPOS="${LPM_ROOT}/repos"
LPM_CACHE="/var/cache/lpm/packages"
LPM_LOGS="${LPM_ROOT}/logs"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Initialize database
init_db() {
    if [ ! -f "$LPM_DB" ]; then
        mkdir -p "$(dirname "$LPM_DB")"
        cat > "$LPM_DB" << 'DBHEADER'
# LPM Package Database
# Format: package:version:install_date:install_size:files_list
DBHEADER
        log_info "Package database initialized"
    fi
}

# Install package from source
install_from_source() {
    local pkg_name=$1
    local pkg_url=$2
    local pkg_version=$3

    log_info "Installing $pkg_name-$pkg_version from source"

    cd /sources
    wget "$pkg_url" -O "${pkg_name}-${pkg_version}.tar.gz"
    tar -xzf "${pkg_name}-${pkg_version}.tar.gz"
    cd "${pkg_name}-${pkg_version}"

    # Standard build process
    if [ -f "configure" ]; then
        ./configure --prefix=/usr
    fi

    make -j$(nproc)
    make install DESTDIR=/

    # Record installation
    local install_size=$(du -sb /usr | cut -f1)
    local install_date=$(date +%Y%m%d-%H%M%S)
    echo "${pkg_name}:${pkg_version}:${install_date}:${install_size}:/usr" >> "$LPM_DB"

    log_success "Package $pkg_name installed"
}

# Install binary package
install_package() {
    local pkg_file=$1

    if [ ! -f "$pkg_file" ]; then
        log_error "Package file not found: $pkg_file"
        return 1
    fi

    log_info "Installing package: $pkg_file"

    # Extract package metadata
    local pkg_name=$(tar -xf "$pkg_file" -O ./metadata/name 2>/dev/null)
    local pkg_version=$(tar -xf "$pkg_file" -O ./metadata/version 2>/dev/null)

    # Extract and install
    tar -xf "$pkg_file" -C /

    # Record installation
    echo "${pkg_name}:${pkg_version}:$(date +%Y%m%d-%H%M%S):0:/" >> "$LPM_DB"

    log_success "Package $pkg_name installed successfully"
}

# Remove package
remove_package() {
    local pkg_name=$1

    log_warning "Removing package: $pkg_name"

    # Get package files
    local files=$(grep "^${pkg_name}:" "$LPM_DB" | cut -d: -f5)

    # Remove files (careful!)
    if [ -n "$files" ]; then
        for file in $(echo "$files" | tr ',' '\n'); do
            rm -f "$file" 2>/dev/null
        done
    fi

    # Remove from database
    sed -i "/^${pkg_name}:/d" "$LPM_DB"

    log_success "Package $pkg_name removed"
}

# List installed packages
list_packages() {
    echo "Installed packages:"
    echo "=================="
    column -t -s':' < "$LPM_DB" | head -n -1
}

# Search packages
search_packages() {
    local pattern=$1
    grep -i "$pattern" "$LPM_DB" || echo "No packages found matching: $pattern"
}

# Update package database from repos
update_repos() {
    log_info "Updating package repositories"

    for repo in /etc/lpm/repos.d/*.repo; do
        if [ -f "$repo" ]; then
            source "$repo"
            log_info "Updating from: $REPO_NAME"
            wget -O "${LPM_REPOS}/${REPO_NAME}.db" "${REPO_URL}/packages.db"
        fi
    done

    log_success "Repository update complete"
}

# Show package info
show_info() {
    local pkg_name=$1

    if grep -q "^${pkg_name}:" "$LPM_DB"; then
        echo "Package: $pkg_name"
        grep "^${pkg_name}:" "$LPM_DB" | while IFS=':' read -r name version date size files; do
            echo "Version: $version"
            echo "Installation date: $date"
            echo "Size: $size bytes"
            echo "Files: $files"
        done
    else
        log_error "Package not found: $pkg_name"
    fi
}

# Create package from installed files
create_package() {
    local pkg_name=$1
    local pkg_version=$2

    log_info "Creating package: $pkg_name-$pkg_version"

    local pkg_dir="/tmp/pkg-${pkg_name}"
    mkdir -p "$pkg_dir/metadata"

    # Create metadata
    cat > "$pkg_dir/metadata/name" <<< "$pkg_name"
    cat > "$pkg_dir/metadata/version" <<< "$pkg_version"
    cat > "$pkg_dir/metadata/dependencies" <<< ""
    cat > "$pkg_dir/metadata/description" <<< "Package created by user"

    # Ask for files to include
    echo "Enter files/directories to include (space-separated):"
    read -r files

    for file in $files; do
        cp -r "$file" "$pkg_dir/"
    done

    # Create archive
    cd /tmp
    tar -czf "${pkg_name}-${pkg_version}.lpm" "pkg-${pkg_name}"
    mv "${pkg_name}-${pkg_version}.lpm" .
    rm -rf "$pkg_dir"

    log_success "Package created: ${pkg_name}-${pkg_version}.lpm"
}

# Main command handler
case "${1:-help}" in
    install)
        if [ -f "$2" ]; then
            install_package "$2"
        else
            install_from_source "$2" "$3" "$4"
        fi
        ;;
    remove|uninstall)
        remove_package "$2"
        ;;
    list|ls)
        list_packages
        ;;
    search)
        search_packages "$2"
        ;;
    info)
        show_info "$2"
        ;;
    update)
        update_repos
        ;;
    create)
        create_package "$2" "$3"
        ;;
    help|--help|-h)
        cat << 'HELP'
LPM - LFS Package Manager

Usage:
  lpm install <package.lpm>           Install binary package
  lpm install <name> <url> <version>  Install from source
  lpm remove <package>                Remove package
  lpm list                            List installed packages
  lpm search <pattern>                Search packages
  lpm info <package>                  Show package info
  lpm update                          Update repository database
  lpm create <name> <version>         Create package from installed files

HELP
        ;;
    *)
        log_error "Unknown command: $1"
        echo "Run 'lpm help' for usage"
        exit 1
        ;;
esac
EOF

chmod +x /usr/bin/lpm

###############################################################################
# REPOSITORY CONFIGURATION
###############################################################################

cat > /etc/lpm/repos.d/official.repo << 'EOF'
# Official LPM Repository
REPO_NAME="official"
REPO_URL="https://repos.linuxfromscratch.org/lpm"
REPO_ENABLED="yes"
REPO_PRIORITY="1"
EOF

cat > /etc/lpm/repos.d/community.repo << 'EOF'
# Community Repository
REPO_NAME="community"
REPO_URL="https://community.lfs.org/lpm"
REPO_ENABLED="yes"
REPO_PRIORITY="2"
EOF

###############################################################################
# PACKAGE BUILD SYSTEM
###############################################################################

cat > /usr/bin/lpm-build << 'EOF'
#!/bin/bash
# LPM Build System - Create packages from PKGBUILD files

set -e

LPM_CACHE="/var/cache/lpm"
SRCDEST="${LPM_CACHE}/sources"
PKGDEST="${LPM_CACHE}/packages"

mkdir -p "$SRCDEST" "$PKGDEST"

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[0;34m[SUCCESS]\033[0m $1"; }

build_package() {
    local pkgbuild_dir=$1

    if [ ! -f "${pkgbuild_dir}/PKGBUILD" ]; then
        echo "Error: PKGBUILD not found in $pkgbuild_dir"
        exit 1
    fi

    source "${pkgbuild_dir}/PKGBUILD"

    log_info "Building $pkgname-$pkgver"

    # Download sources
    cd "$SRCDEST"
    for url in "${source[@]}"; do
        wget -nc "$url"
    done

    # Extract and build
    cd "$pkgbuild_dir"

    # Run build functions if they exist
    if declare -f prepare >/dev/null; then prepare; fi
    if declare -f build >/dev/null; then build; fi
    if declare -f check >/dev/null; then check; fi

    # Create package
    local pkg_file="${PKGDEST}/${pkgname}-${pkgver}.lpm"
    tar -czf "$pkg_file" /usr/* 2>/dev/null || true

    log_success "Package created: $pkg_file"
}

# PKGBUILD template
create_pkgbuild() {
    local pkg_name=$1

    cat > "PKGBUILD" << 'PKG_TEMPLATE'
# Maintainer: Your Name <email@example.com>
pkgname=my-package
pkgver=1.0.0
pkgrel=1
pkgdesc="A sample package"
arch=('x86_64')
url="https://example.com"
license=('GPL')
depends=('glibc' 'gcc')
makedepends=('make')
source=("https://example.com/${pkgname}-${pkgver}.tar.gz")
sha256sums=('SKIP')

prepare() {
    cd "${srcdir}/${pkgname}-${pkgver}"
    ./configure --prefix=/usr
}

build() {
    cd "${srcdir}/${pkgname}-${pkgver}"
    make
}

check() {
    cd "${srcdir}/${pkgname}-${pkgver}"
    make check
}

package() {
    cd "${srcdir}/${pkgname}-${pkgver}"
    make install DESTDIR="${pkgdir}"
}
PKG_TEMPLATE

    # Replace template values
    sed -i "s/my-package/${pkg_name}/g" PKGBUILD

    log_success "PKGBUILD created for $pkg_name"
}

case "${1:-help}" in
    build)
        build_package "$2"
        ;;
    create)
        create_pkgbuild "$2"
        ;;
    *)
        echo "Usage: lpm-build <build|create> [directory]"
        ;;
esac
EOF

chmod +x /usr/bin/lpm-build

###############################################################################
# SYSTEM INTEGRATION - Add to PATH
###############################################################################

cat > /etc/profile.d/lpm.sh << 'EOF'
# LPM Package Manager
export LPM_ROOT="/var/lib/lpm"
export LPM_CACHE="/var/cache/lpm"
export PATH="/usr/bin:${PATH}"
EOF

chmod +x /etc/profile.d/lpm.sh

###############################################################################
# COMPLETION SCRIPT (Bash auto-completion)
###############################################################################

cat > /etc/bash_completion.d/lpm << 'EOF'
_lpm_completion() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    opts="install remove list search info update create help"

    case "${prev}" in
        install|remove|info)
            # Suggest installed packages
            COMPREPLY=($(compgen -W "$(grep -v '^#' /var/lib/lpm/packages.db | cut -d: -f1)" -- ${cur}))
            return 0
            ;;
        *)
            COMPREPLY=($(compgen -W "${opts}" -- ${cur}))
            return 0
            ;;
    esac
}
complete -F _lpm_completion lpm
EOF

log_success "LPM Package Manager installed successfully"
log_success "Version: $LPM_VERSION"

echo ""
echo "LPM Commands:"
echo "  lpm install <package.lpm>    - Install binary package"
echo "  lpm install <name> <url> <ver> - Install from source"
echo "  lpm remove <package>         - Remove package"
echo "  lpm list                     - List installed packages"
echo "  lpm search <pattern>         - Search packages"
echo "  lpm create <name> <version>  - Create package"
echo ""
echo "lpm-build commands:"
echo "  lpm-build create <name>      - Create PKGBUILD template"
echo "  lpm-build build <dir>        - Build package from PKGBUILD"