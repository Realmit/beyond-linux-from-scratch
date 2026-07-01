#!/bin/bash
# Init System Selector - User interface for choosing init system
# Run this BEFORE building LFS

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_banner() {
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════════════════════╗
║                                                                               ║
║     ██╗     ███████╗███████╗    ██╗███╗   ██╗██╗████████╗                     ║
║     ██║     ██╔════╝██╔════╝    ██║████╗  ██║██║╚══██╔══╝                     ║
║     ██║     █████╗  ███████╗    ██║██╔██╗ ██║██║   ██║                        ║
║     ██║     ██╔══╝  ╚════██║    ██║██║╚██╗██║██║   ██║                        ║
║     ███████╗██║     ███████║    ██║██║ ╚████║██║   ██║                        ║
║     ╚══════╝╚═╝     ╚══════╝    ╚═╝╚═╝  ╚═══╝╚═╝   ╚═╝                        ║
║                                                                               ║
║                    INIT SYSTEM SELECTOR v2.0                                  ║
║                                                                               ║
╚═══════════════════════════════════════════════════════════════════════════════╝
EOF
}

print_options() {
    echo -e "${CYAN}"
    echo "┌─────────────────────────────────────────────────────────────────────────┐"
    echo "│                         CHOOSE YOUR INIT SYSTEM                         │"
    echo "├─────────────────────────────────────────────────────────────────────────┤"
    echo -e "│ ${GREEN}1) sysvinit${NC} - Traditional UNIX init (LFS Old School)                    │"
    echo "│                                                                         │"
    echo "│   Simple and transparent                                            │"
    echo "│   Easy to debug and understand                                      │"
    echo "│   Small footprint (~500KB)                                          │"
    echo "│   Classic LFS experience                                            │"
    echo "│   Works with simple shell scripts                                   │"
    echo "│   No parallel boot                                                  │"
    echo "│   No automatic dependency resolution                                │"
    echo "│                                                                         │"
    echo "├─────────────────────────────────────────────────────────────────────────┤"
    echo -e "│ ${BLUE}2) systemd${NC} - Modern init (Recommended for desktops)                     │"
    echo "│                                                                         │"
    echo "│   Parallel boot (faster startup)                                    │"
    echo "│   Automatic dependency resolution                                   │"
    echo "│   Built-in service management                                       │"
    echo "│   Integrated logging (journald)                                     │"
    echo "│   Socket activation and cgroups                                     │"
    echo "│   More complex (~10MB)                                              │"
    echo "│   Steeper learning curve                                            │"
    echo "│                                                                         │"
    echo "├─────────────────────────────────────────────────────────────────────────┤"
    echo -e "│ ${YELLOW}3) openrc${NC}    - Gentoo-style dependency-based init                      │"
    echo "│   (Best of both worlds: simple but dependency-aware)                   │"
    echo "├─────────────────────────────────────────────────────────────────────────┤"
    echo -e "│ ${YELLOW}4) runit${NC}      - Simple supervision suite (minimalist)                   │"
    echo "├─────────────────────────────────────────────────────────────────────────┤"
    echo -e "│ ${YELLOW}5) s6${NC}         - Small supervision suite (security-focused)               │"
    echo "└─────────────────────────────────────────────────────────────────────────┘"
    echo -e "${NC}"
}

print_comparison() {
    echo -e "\n${CYAN}📊 Quick Comparison:${NC}"
    echo "  ┌──────────┬────────────┬────────────┬────────────┬────────────┐"
    echo "  │ Feature  │  sysvinit  │  systemd   │   openrc   │   runit    │"
    echo "  ├──────────┼────────────┼────────────┼────────────┼────────────┤"
    echo "  │ Size     │   ~500KB   │   ~10MB    │   ~2MB     │   ~300KB   │"
    echo "  │ Speed    │   Slow     │   Fast     │   Medium   │   Fast     │"
    echo "  │ Parallel │    No      │    Yes     │    Yes     │    Yes     │"
    echo "  │ Deps     │   Manual   │  Auto      │   Auto     │   Manual   │
    echo "  │ Logging  │   Syslog   │ journald   │   Syslog   │   Syslog   │"
    echo "  │ Learning │   Easy     │  Complex   │   Medium   │   Easy     │"
    echo "  └──────────┴────────────┴────────────┴────────────┴────────────┘"
}

show_recommendation() {
    echo -e "\n${GREEN}💡 Recommendation:${NC}"
    echo "  - For servers or minimal systems: ${BLUE}sysvinit${NC} or ${BLUE}runit${NC}"
    echo "  - For desktop environments (GNOME/KDE): ${BLUE}systemd${NC}"
    echo "  - For embedded systems: ${BLUE}s6${NC} or ${BLUE}runit${NC}"
    echo "  - For a balanced approach: ${BLUE}openrc${NC}"
}

select_style() {
    if [ "$1" = "sysvinit" ]; then
        echo -e "\n${CYAN}┌─────────────────────────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│                    SYSVINIT BOOT SCRIPT STYLE                              │${NC}"
        echo -e "${CYAN}├─────────────────────────────────────────────────────────────────────────┤${NC}"
        echo -e "│ ${GREEN}a) LFS Classic${NC} - Original LFS bootscripts (/etc/rc.d/rc0.d...rc6.d)     │"
        echo -e "│ ${GREEN}b) BSD-style${NC}  - FreeBSD/NetBSD style (/etc/rc.d/rcS.d, rc.conf)        │"
        echo -e "${CYAN}└─────────────────────────────────────────────────────────────────────────┘${NC}"

        read -p "Choose style [a/b] (default: a): " style_choice
        case "$style_choice" in
            b|B|bsd|BSD) SYSVINIT_STYLE="bsd-style" ;;
            *) SYSVINIT_STYLE="lfs-classic" ;;
        esac
        echo -e "${GREEN}✓ Selected: $SYSVINIT_STYLE${NC}"
    fi
}

save_config() {
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/init.conf" << EOF
# ============================================================================
# INIT SYSTEM CONFIGURATION
# Generated by init-selector.sh on $(date)
# ============================================================================

# Selected init system: $1
INIT_SYSTEM="$1"

# For sysvinit: style can be "lfs-classic" or "bsd-style"
SYSVINIT_STYLE="${2:-lfs-classic}"

# For openrc: enable parallel startup
OPENRC_PARALLEL="true"

# For systemd: network management
USE_SYSTEMD_RESOLVED="true"
USE_SYSTEMD_NETWORKD="false"

# For runit/s6: service directory
SERVICE_DIR="/etc/service"
EOF
    echo -e "${GREEN}✓ Configuration saved to $CONFIG_DIR/init.conf${NC}"
}

main() {
    print_banner
    print_options
    print_comparison
    show_recommendation

    echo -e "\n${YELLOW}Enter your choice (1-5) [default: 1]:${NC} "
    read -r choice

    case "$choice" in
        2|systemd|Systemd)
            INIT_SYSTEM="systemd"
            STYLE=""
            echo -e "${GREEN}✓ Selected: systemd (modern init)${NC}"
            ;;
        3|openrc|OpenRC)
            INIT_SYSTEM="openrc"
            STYLE=""
            echo -e "${GREEN}✓ Selected: openrc (dependency-based init)${NC}"
            echo -e "${YELLOW}⚠ Note: openrc requires additional setup beyond LFS core${NC}"
            ;;
        4|runit|Runit)
            INIT_SYSTEM="runit"
            STYLE=""
            echo -e "${GREEN}✓ Selected: runit (simple supervision)${NC}"
            echo -e "${YELLOW}⚠ Note: runit requires additional installation${NC}"
            ;;
        5|s6|S6)
            INIT_SYSTEM="s6"
            STYLE=""
            echo -e "${GREEN}✓ Selected: s6 (small supervision suite)${NC}"
            echo -e "${YELLOW}⚠ Note: s6 requires additional installation${NC}"
            ;;
        *|1|sysvinit|SysVinit)
            INIT_SYSTEM="sysvinit"
            select_style "sysvinit"
            ;;
    esac

    save_config "$INIT_SYSTEM" "$SYSVINIT_STYLE"

    echo -e "\n${GREEN}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✓ Init system configured successfully!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "You can now run: ./lfs/06-build-lfs-system.sh"
    echo "To change later, edit: config/init.conf"
}

main "$@"