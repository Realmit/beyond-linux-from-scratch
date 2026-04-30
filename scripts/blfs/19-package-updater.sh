#!/bin/bash
# LPM Package Manager - Upgrade functionality extension

create_upgrade_commands() {
    log_info "Adding upgrade commands to LPM..."

    # Add upgrade functions to existing lpm script
    cat >> /usr/bin/lpm << 'LPMUPGRADE'

# ============================================================================
# UPGRADE FUNCTIONS
# ============================================================================

# List outdated packages
list_outdated() {
    log_info "Checking for outdated packages..."

    for pkg in $(grep -v '^#' "$LPM_DB" | cut -d: -f1); do
        current_version=$(grep "^${pkg}:" "$LPM_DB" | cut -d: -f2)
        latest_version=$(get_latest_version "$pkg")

        if [ "$current_version" != "$latest_version" ] && [ -n "$latest_version" ]; then
            echo "$pkg: $current_version -> $latest_version"
        fi
    done
}

# Get latest version from repository
get_latest_version() {
    local pkg=$1
    local repo_file="${LPM_REPOS}/official.db"

    if [ -f "$repo_file" ]; then
        grep "^${pkg}:" "$repo_file" | cut -d: -f2 | head -1
    fi
}

# Upgrade single package
upgrade_single() {
    local pkg=$1

    log_info "Upgrading package: $pkg"

    # Get latest version and URL
    local latest_version=$(get_latest_version "$pkg")
    local pkg_url=$(grep "^${pkg}:" "${LPM_REPOS}/official.db" | cut -d: -f4)

    if [ -z "$pkg_url" ]; then
        log_error "Package not found in repositories: $pkg"
        return 1
    fi

    # Remove old version
    remove_package "$pkg"

    # Install new version
    install_from_source "$pkg" "$pkg_url" "$latest_version"

    log_success "Upgraded: $pkg"
}

# Upgrade all packages
upgrade_all() {
    log_info "Upgrading all packages..."

    local outdated=$(list_outdated | cut -d: -f1)

    if [ -z "$outdated" ]; then
        log_info "All packages are up to date"
        return 0
    fi

    for pkg in $outdated; do
        upgrade_single "$pkg"
    done

    log_success "All packages upgraded"
}

# Add to case statement (modify existing case)
# Add these lines to the case statement in /usr/bin/lpm:
#
# upgrade)
#     if [ -n "$2" ]; then
#         upgrade_single "$2"
#     else
#         upgrade_all
#     fi
#     ;;
# list-outdated)
#     list_outdated
#     ;;
LPMUPGRADE

    # Actually modify the lpm script to include upgrade case
    if [ -f /usr/bin/lpm ]; then
        # Create temporary file with upgrade commands
        cat > /tmp/lpm-upgrade-patch << 'EOF'
    upgrade)
        if [ -n "$2" ]; then
            upgrade_single "$2"
        else
            upgrade_all
        fi
        ;;
    list-outdated)
        list_outdated
        ;;
EOF

        # Insert before help case
        sed -i '/help|--help|-h)/i \ \ \ \ upgrade)\n        if [ -n "$2" ]; then\n            upgrade_single "$2"\n        else\n            upgrade_all\n        fi\n        ;;\n    list-outdated)\n        list_outdated\n        ;;' /usr/bin/lpm
    fi

    log_success "Upgrade commands added to LPM"
}