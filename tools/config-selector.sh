#!/bin/bash
# Configuration selector - choose between different build configs

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/../config"
BUILD_CONF="${CONFIG_DIR}/build.conf"

# Available configs
declare -A CONFIGS=(
    ["default"]="build.conf"
    ["minimal"]="build.conf.minimal"
    ["java"]="build.conf.java"
    ["server"]="build.conf.minimal"
    ["desktop"]="build.conf"
    ["full"]="build.conf"
)

show_menu() {
    echo "========================================="
    echo "LFS Build Configuration Selector"
    echo "========================================="
    echo ""
    echo "Available configurations:"
    echo "  1) default  - Standard desktop with XFCE"
    echo "  2) minimal  - Minimal server (no desktop)"
    echo "  3) java     - Java development environment"
    echo "  4) server   - Lightweight server config"
    echo ""
    echo "  c) Custom - Edit configuration manually"
    echo "  q) Quit"
    echo ""
}

select_config() {
    local choice=$1
    local config_file=""

    case $choice in
        1|default)
            config_file="build.conf"
            ;;
        2|minimal)
            config_file="build.conf.minimal"
            ;;
        3|java)
            config_file="build.conf.java"
            ;;
        4|server)
            config_file="build.conf.minimal"
            ;;
        c|custom)
            ${EDITOR:-vi} "$BUILD_CONF"
            echo "Configuration updated"
            return
            ;;
        q|quit)
            exit 0
            ;;
        *)
            echo "Invalid choice"
            return 1
            ;;
    esac

    if [ -f "${CONFIG_DIR}/$config_file" ]; then
        cp "${CONFIG_DIR}/$config_file" "$BUILD_CONF"
        echo "Configuration set to: $config_file"
        echo ""
        echo "Current settings:"
        echo "  Init system: $(grep -A2 '"init_system"' "$BUILD_CONF" | grep choice | cut -d'"' -f4)"
        echo "  Desktop: $(grep -A5 '"desktop"' "$BUILD_CONF" | grep type | cut -d'"' -f4)"
        echo "  Java Dev: $(grep -A2 '"java_dev"' "$BUILD_CONF" | grep enabled | cut -d':' -f2 | tr -d ' ,')"
        echo "  Package manager: $(grep -A2 '"package_manager"' "$BUILD_CONF" | grep enabled | cut -d':' -f2 | tr -d ' ,')"
    else
        echo "Configuration file not found: $config_file"
    fi
}

# Main
if [ "$1" != "" ]; then
    select_config "$1"
else
    show_menu
    read -p "Select configuration [1-4/c/q]: " choice
    select_config "$choice"
fi