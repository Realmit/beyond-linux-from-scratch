#!/bin/bash
# Load packages from config files

load_packages_from_conf() {
    local conf_file="${1:-/etc/lfs/packages.conf}"

    if [ ! -f "$conf_file" ]; then
        log_error "Packages config not found: $conf_file"
        return 1
    fi

    log_info "Loading packages from $conf_file"

    # Parse the packages.conf file
    while IFS='|' read -r category name version url md5; do
        # Skip comments and empty lines
        [[ "$category" =~ ^#.*$ ]] && continue
        [[ -z "$category" ]] && continue

        log_info "Found package: $category/$name-$version"

        # Download if not exists
        if [ ! -f "/sources/${name}-${version}.tar.*" ]; then
            wget "$url" -O "/sources/${name}-${version}.tar.xz"
        fi

    done < "$conf_file"
}

load_json_config() {
    local json_file="${1:-/etc/lfs/packages.conf.json}"

    if command -v jq &> /dev/null && [ -f "$json_file" ]; then
        log_info "Loading JSON package config"

        # Extract enabled packages
        local packages=$(jq -r '.categories[].packages[]?.name' "$json_file")

        for pkg in $packages; do
            log_info "Package: $pkg"
        done
    else
        log_warning "jq not installed, using text config"
    fi
}

# Main
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    load_packages_from_conf "config/packages.conf"
fi