#!/bin/bash
# First boot script - runs once after first system start
# Location: /etc/profile.d/first-boot.sh or systemd service

set -e

FIRST_BOOT_FLAG="/var/lib/.first-boot-done"

# Exit if already ran once
if [ -f "$FIRST_BOOT_FLAG" ]; then
    exit 0
fi

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[0;34m[SUCCESS]\033[0m $1"; }
log_warning() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }

# ----------------------------------------------------------------------------
# HARDWARE DETECTION
# ----------------------------------------------------------------------------
detect_hardware() {
    log_info "Detecting hardware..."

    # CPU
    CPU_VENDOR=$(lscpu | grep "Vendor ID" | cut -d: -f2 | xargs)
    CPU_CORES=$(nproc)
    echo "CPU: $CPU_VENDOR, $CPU_CORES cores"

    # RAM
    RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
    echo "RAM: ${RAM_GB}GB"

    # GPU
    if lspci | grep -i vga | grep -qi nvidia; then
        GPU="nvidia"
    elif lspci | grep -i vga | grep -qi amd; then
        GPU="amd"
    elif lspci | grep -i vga | grep -qi intel; then
        GPU="intel"
    else
        GPU="unknown"
    fi
    echo "GPU: $GPU"

    # Save to /etc/hardware-profile
    cat > /etc/hardware-profile << EOF
CPU_VENDOR="$CPU_VENDOR"
CPU_CORES="$CPU_CORES"
RAM_GB="$RAM_GB"
GPU="$GPU"
EOF
}

# ----------------------------------------------------------------------------
# AUTO-CONFIGURE GRAPHICS DRIVERS
# ----------------------------------------------------------------------------
setup_graphics() {
    log_info "Setting up graphics..."

    source /etc/hardware-profile

    case "$GPU" in
        nvidia)
            log_info "NVIDIA GPU detected, installing proprietary drivers..."
            # Install NVIDIA drivers if available
            if [ -f /sources/NVIDIA-*.run ]; then
                /sources/NVIDIA-*.run --silent
            fi
            ;;
        amd)
            log_info "AMD GPU detected, using open-source drivers..."
            # AMD drivers are in kernel
            ;;
        intel)
            log_info "Intel GPU detected, configuring..."
            # Intel drivers are in kernel
            ;;
    esac
}

# ----------------------------------------------------------------------------
# NETWORK CONFIGURATION ASSISTANT
# ----------------------------------------------------------------------------
configure_network() {
    log_info "Configuring network..."

    # Detect network interfaces
    INTERFACES=$(ip link show | grep -E '^[0-9]+: e' | cut -d: -f2 | xargs)

    if [ -z "$INTERFACES" ]; then
        log_warning "No ethernet interfaces found"
        return
    fi

    # Try DHCP on each interface
    for iface in $INTERFACES; do
        log_info "Configuring $iface with DHCP..."
        dhcpcd "$iface" 2>/dev/null || dhclient "$iface" 2>/dev/null || true
    done

    # Test connection
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log_success "Network connected!"
    else
        log_warning "Network connection failed. Manual configuration needed."
    fi
}

# ----------------------------------------------------------------------------
# CREATE DEFAULT USER CONFIGURATIONS
# ----------------------------------------------------------------------------
configure_user_env() {
    log_info "Configuring user environments..."

    for user_home in /home/*; do
        if [ -d "$user_home" ]; then
            username=$(basename "$user_home")

            # Bash configuration
            cat >> "$user_home/.bashrc" << 'EOF'

# Custom LS colors
eval "$(dircolors -b)"

# Aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'
alias ..='cd ..'
alias ...='cd ../..'

# Prompt
PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

# History
HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoreboth
HISTTIMEFORMAT="%F %T "

# PATH
export PATH="$HOME/.local/bin:$PATH"
EOF

            # Create user directories
            mkdir -p "$user_home"/{Documents,Downloads,Music,Pictures,Videos,Projects,.local/bin}

            # Set ownership
            chown -R "$username:$username" "$user_home"
        fi
    done
}

# ----------------------------------------------------------------------------
# ENABLE SERVICES BASED ON HARDWARE
# ----------------------------------------------------------------------------
enable_services() {
    log_info "Enabling system services..."

    # Always enable
    systemctl enable systemd-networkd 2>/dev/null || true
    systemctl enable systemd-resolved 2>/dev/null || true
    systemctl enable dbus 2>/dev/null || true

    # Enable if hardware supports
    if command -v bluetoothd >/dev/null 2>&1; then
        systemctl enable bluetooth 2>/dev/null || true
    fi

    if command -v cupsd >/dev/null 2>&1; then
        systemctl enable cups 2>/dev/null || true
    fi

    # Enable display manager if present
    if systemctl list-unit-files | grep -q lightdm; then
        systemctl enable lightdm 2>/dev/null || true
        systemctl set-default graphical.target
    elif systemctl list-unit-files | grep -q gdm; then
        systemctl enable gdm 2>/dev/null || true
        systemctl set-default graphical.target
    fi
}

# ----------------------------------------------------------------------------
# PERFORM SYSTEM UPDATE (if package manager exists)
# ----------------------------------------------------------------------------
check_updates() {
    log_info "Checking for updates..."

    if command -v lpm >/dev/null 2>&1; then
        lpm update 2>/dev/null || true
    fi
}

# ----------------------------------------------------------------------------
# CREATE WELCOME MESSAGE
# ----------------------------------------------------------------------------
create_welcome() {
    cat > /etc/profile.d/welcome.sh << 'EOF'
#!/bin/bash

if [ "$PS1" ]; then
    echo "=================================================="
    echo "  Welcome to LFS Linux $(cat /etc/lfs-release 2>/dev/null)"
    echo "=================================================="
    echo "  Kernel: $(uname -r)"
    echo "  CPU: $(nproc) cores"
    echo "  RAM: $(free -h | awk '/^Mem:/{print $2}')"
    echo "=================================================="
    echo ""
fi
EOF
    chmod +x /etc/profile.d/welcome.sh
}

# ----------------------------------------------------------------------------
# FIRST BOOT COMPLETE
# ----------------------------------------------------------------------------
first_boot_complete() {
    touch "$FIRST_BOOT_FLAG"
    log_success "First boot setup complete!"
}

# ----------------------------------------------------------------------------
# MAIN
# ----------------------------------------------------------------------------
main() {
    log_info "=== FIRST BOOT SETUP ==="

    # Must run as root
    if [ "$EUID" -ne 0 ]; then
        log_warning "First boot script requires root privileges"
        exit 1
    fi

    detect_hardware
    setup_graphics
    configure_network
    configure_user_env
    enable_services
    check_updates
    create_welcome
    first_boot_complete

    log_success "System ready!"
    echo ""
    echo "=================================================="
    echo "  LFS LINUX IS NOW READY FOR USE"
    echo "=================================================="
    echo "  Login with your username and password"
    echo ""
}

main "$@"