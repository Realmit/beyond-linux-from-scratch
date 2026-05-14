#!/bin/bash
# Audio Profile Selector - Choose between CLI or Desktop

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

print_banner() {
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════════════════════╗
║                                                                               ║
║     █████╗ ██╗   ██╗██████╗ ██╗ ██████╗     ██████╗ ██████╗  ██████╗ ███████╗ ║
║    ██╔══██╗██║   ██║██╔══██╗██║██╔═══██╗    ██╔══██╗██╔══██╗██╔═══██╗██╔════╝ ║
║    ███████║██║   ██║██║  ██║██║██║   ██║    ██████╔╝██████╔╝██║   ██║█████╗   ║
║    ██╔══██║██║   ██║██║  ██║██║██║   ██║    ██╔═══╝ ██╔══██╗██║   ██║██╔══╝   ║
║    ██║  ██║╚██████╔╝██████╔╝██║╚██████╔╝    ██║     ██║  ██║╚██████╔╝███████╗ ║
║    ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚═╝ ╚═════╝     ╚═╝     ╚═╝  ╚═╝ ╚═════╝ ╚══════╝ ║
║                                                                               ║
║                    AUDIO PRODUCTION PROFILE SELECTOR                          ║
║                                                                               ║
╚═══════════════════════════════════════════════════════════════════════════════╝
EOF
}

print_profiles() {
    echo -e "\n${CYAN}┌─────────────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│                    SELECT YOUR AUDIO WORKSTATION TYPE                      │${NC}"
    echo -e "${CYAN}├─────────────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│                                                                         │${NC}"

    echo -e "│  ${GREEN}1) CLI Minimal${NC} - Terminal-only audio production                     │"
    echo -e "│     • Command-line tools only (SoX, ecasound, fluidsynth)                    │"
    echo -e "│     • No X11/display server required                                         │"
    echo -e "│     • Low memory usage (~256MB RAM)                                          │"
    echo -e "│     • Ideal for: Headless servers, embedded devices, remote production      │"
    echo -e "│     • Tools: JACK2, ALSA, MIDI tools, audio analysis                         │"
    echo -e "${CYAN}│                                                                         │${NC}"

    echo -e "│  ${BLUE}2) XFCE Desktop${NC} - Lightweight GUI audio workstation                   │"
    echo -e "│     • XFCE4 desktop environment                                              │"
    echo -e "│     • Audacity, Ardour, Qtractor with GUI                                    │"
    echo -e "│     • Moderate resource usage (~1GB RAM)                                     │"
    echo -e "│     • Ideal for: Laptop/desktop production, live performance                │"
    echo -e "│     • Tools: Full GUI DAWs + all CLI tools                                   │"
    echo -e "${CYAN}│                                                                         │${NC}"

    echo -e "│  ${MAGENTA}3) GNOME Desktop${NC} - Full-featured audio workstation                 │"
    echo -e "│     • GNOME 46 desktop environment                                           │"
    echo -e "│     • Professional DAWs: Ardour, LMMS, Bitwig (optional)                     │"
    echo -e "│     • PipeWire + JACK + PulseAudio integration                               │"
    echo -e "│     • Higher resource usage (~2GB RAM)                                       │"
    echo -e "│     • Ideal for: Professional studio, post-production                       │"
    echo -e "│     • Tools: GNOME Music, Podcasts, full plugin suite                       │"
    echo -e "${CYAN}│                                                                         │${NC}"

    echo -e "│  ${YELLOW}4) Studio Full${NC} - Complete professional workstation (50GB+)          │"
    echo -e "│     • KDE Plasma desktop                                                     │"
    echo -e "│     • All DAWs: Ardour, LMMS, Qtractor, Rosegarden                          │"
    echo -e "│     • All plugins: Calf, LSP, Dragonfly, x42, zam, swh                       │"
    echo -e "│     • Sound libraries: Multiple GB of samples and soundfonts                │"
    echo -e "│     • Video editing: Kdenlive, Blender audio                                 │"
    echo -e "│     • Ideal for: Professional studio, film scoring, game audio              │"
    echo -e "${CYAN}│                                                                         │${NC}"

    echo -e "│  ${YELLOW}5) Custom${NC} - Select individual components                           │"
    echo -e "│     • Choose specific audio servers, DAWs, plugins                           │"
    echo -e "│     • Build your own custom environment                                      │"
    echo -e "${CYAN}│                                                                         │${NC}"

    echo -e "${CYAN}└─────────────────────────────────────────────────────────────────────────┘${NC}"
}

print_comparison() {
    echo -e "\n${CYAN}📊 Feature Comparison:${NC}"
    echo ""
    printf "  ${GREEN}%-20s${NC} ${BLUE}%-20s${NC} ${MAGENTA}%-20s${NC} ${YELLOW}%-20s${NC}\n" "Feature" "CLI Minimal" "XFCE Desktop" "Full Studio"
    echo "  ─────────────────────────────────────────────────────────────────────────────"
    printf "  %-20s %-20s %-20s %-20s\n" "Memory usage" "~256MB" "~1GB" "~2GB+"
    printf "  %-20s %-20s %-20s %-20s\n" "Disk space" "~1.5GB" "~8GB" "~30GB+"
    printf "  %-20s %-20s %-20s %-20s\n" "GUI available" "No" "Yes (XFCE)" "Yes (KDE/GNOME)"
    printf "  %-20s %-20s %-20s %-20s\n" "Real-time kernel" "Optional" "Yes" "Yes"
    printf "  %-20s %-20s %-20s %-20s\n" "JACK2" "✓" "✓" "✓"
    printf "  %-20s %-20s %-20s %-20s\n" "PipeWire" "✓" "✓" "✓"
    printf "  %-20s %-20s %-20s %-20s\n" "MIDI sequencing" "CLI only" "GUI + CLI" "Professional"
    printf "  %-20s %-20s %-20s %-20s\n" "Plugin support" "LV2/LADSPA" "All formats" "All + VST3"
    printf "  %-20s %-20s %-20s %-20s\n" "Sample libraries" "Minimal" "Medium" "Full"
}

show_recommendations() {
    echo -e "\n${GREEN}💡 Recommendations:${NC}"
    echo ""
    echo "  • ${GREEN}CLI Minimal${NC}  → Headless server, Raspberry Pi, remote production, batch processing"
    echo "  • ${BLUE}XFCE Desktop${NC} → Lightweight studio, laptop, live performance, budget hardware"
    echo "  • ${MAGENTA}GNOME Desktop${NC}→ Professional studio, podcast production, post-processing"
    echo "  • ${YELLOW}Studio Full${NC}  → Professional composer, film scoring, game audio, mastering"
}

select_profile() {
    echo -e "\n${YELLOW}Enter your choice (1-5) [default: 2]:${NC} "
    read -r choice

    case "$choice" in
        1|cli|minimal|CLI)
            PROFILE="cli-minimal"
            echo -e "${GREEN}✓ Selected: CLI Minimal (terminal-only audio production)${NC}"
            ;;
        2|xfce|XFCE)
            PROFILE="desktop-xfce"
            echo -e "${GREEN}✓ Selected: XFCE Desktop (lightweight GUI audio workstation)${NC}"
            ;;
        3|gnome|GNOME)
            PROFILE="desktop-gnome"
            echo -e "${GREEN}✓ Selected: GNOME Desktop (full-featured audio workstation)${NC}"
            ;;
        4|studio|full|kde|KDE)
            PROFILE="studio-full"
            echo -e "${GREEN}✓ Selected: Studio Full (complete professional workstation)${NC}"
            ;;
        5|custom|Custom)
            PROFILE="custom"
            echo -e "${GREEN}✓ Selected: Custom - Select individual components${NC}"
            select_custom_components
            ;;
        *)
            PROFILE="desktop-xfce"
            echo -e "${GREEN}✓ Default: XFCE Desktop selected${NC}"
            ;;
    esac

    # Ask about init system preference
    echo -e "\n${YELLOW}Init system preference:${NC}"
    echo "  a) sysvinit (traditional, simpler)"
    echo "  b) systemd (modern, faster boot)"
    read -p "Choice [a/b] (default: a): " init_choice

    case "$init_choice" in
        b|systemd|Systemd) INIT_SYSTEM="systemd" ;;
        *) INIT_SYSTEM="sysvinit" ;;
    esac

    echo -e "${GREEN}✓ Using init system: $INIT_SYSTEM${NC}"
}

select_custom_components() {
    echo -e "\n${CYAN}Custom Component Selection:${NC}"
    echo ""

    # Audio servers
    echo -e "${YELLOW}Audio Servers (select at least one):${NC}"
    read -p "  Install JACK2? [y/N]: " install_jack
    read -p "  Install PipeWire? [y/N]: " install_pipewire
    read -p "  Install PulseAudio? [y/N]: " install_pulse

    # DAWs
    echo -e "\n${YELLOW}Digital Audio Workstations:${NC}"
    read -p "  Install Ardour? [y/N]: " install_ardour
    read -p "  Install LMMS? [y/N]: " install_lmms
    read -p "  Install Qtractor? [y/N]: " install_qtractor
    read -p "  Install Rosegarden? [y/N]: " install_rosegarden

    # GUI vs CLI
    echo -e "\n${YELLOW}Interface Type:${NC}"
    read -p "  Install X11/GUI? [y/N]: " install_gui

    # Plugins
    echo -e "\n${YELLOW}Plugin Collections:${NC}"
    read -p "  Install Calf plugins? [y/N]: " install_calf
    read -p "  Install LSP plugins? [y/N]: " install_lsp
    read -p "  Install Dragonfly Reverb? [y/N]: " install_dragonfly

    # MIDI
    echo -e "\n${YELLOW}MIDI Tools:${NC}"
    read -p "  Install FluidSynth? [y/N]: " install_fluidsynth
    read -p "  Install SoundFonts? [y/N]: " install_soundfonts

    # Save custom config
    cat > "$SCRIPT_DIR/custom.conf" << EOF
# Custom audio profile configuration
INSTALL_JACK2="$install_jack"
INSTALL_PIPEWIRE="$install_pipewire"
INSTALL_PULSE="$install_pulse"
INSTALL_ARDOUR="$install_ardour"
INSTALL_LMMS="$install_lmms"
INSTALL_QTractor="$install_qtractor"
INSTALL_ROSEGARDEN="$install_rosegarden"
INSTALL_GUI="$install_gui"
INSTALL_CALF="$install_calf"
INSTALL_LSP="$install_lsp"
INSTALL_DRAGONFLY="$install_dragonfly"
INSTALL_FLUIDSYNTH="$install_fluidsynth"
INSTALL_SOUNDFONTS="$install_soundfonts"
EOF
}

save_configuration() {
    mkdir -p "$SCRIPT_DIR/../config"

    cat > "$SCRIPT_DIR/../config/audio-profile.conf" << EOF
# ============================================================================
# AUDIO PRODUCTION PROFILE CONFIGURATION
# Generated on $(date)
# ============================================================================

# Selected profile: $PROFILE
AUDIO_PROFILE="$PROFILE"

# Init system preference
INIT_SYSTEM="$INIT_SYSTEM"

# Real-time kernel
RT_KERNEL="${RT_KERNEL:-true}"

# Audio server (auto-detected based on profile)
JACK2_ENABLED="${JACK2_ENABLED:-true}"
PIPEWIRE_ENABLED="${PIPEWIRE_ENABLED:-false}"

# GUI options (based on profile)
GUI_ENABLED="$([ "$PROFILE" != "cli-minimal" ] && echo "true" || echo "false")"
DESKTOP_ENVIRONMENT="${DESKTOP_ENVIRONMENT:-$([ "$PROFILE" = "desktop-gnome" ] && echo "gnome" || echo "xfce")}"

# Sample libraries
SAMPLE_LIBS="${SAMPLE_LIBS:-minimal}"
EOF

    echo -e "${GREEN}✓ Configuration saved to config/audio-profile.conf${NC}"
}

main() {
    clear
    print_banner
    print_profiles
    print_comparison
    show_recommendations
    select_profile
    save_configuration

    echo -e "\n${GREEN}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✓ Audio profile configured successfully!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Run: ./profiles/audio/$PROFILE/build.sh"
    echo "  2. Or build packages: lpm install -p audio-$PROFILE"
    echo ""
    echo "To change later: edit config/audio-profile.conf"
}

main "$@"