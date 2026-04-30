#!/bin/bash
# Minimal Profile for LFS
# Command-line only minimal system

set -e

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[0;34m[SUCCESS]\033[0m $1"; }
log_warning() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }

# ============================================================================
# CONFIGURATION
# ============================================================================

NUM_JOBS=${NUM_JOBS:-$(nproc)}
PACKAGE_LIST="profiles/minimal/packages.list"

# ============================================================================
# INSTALL MINIMAL PACKAGES
# ============================================================================
install_minimal_packages() {
    log_info "Installing minimal system packages..."

    cd /sources

    # Base system packages (order matters!)
    local base_packages=(
        "linux-headers"
        "glibc"
        "gcc"
        "binutils"
        "make"
        "bash"
        "coreutils"
        "util-linux"
        "systemd"
        "procps"
    )

    # Install each package
    for pkg in "${base_packages[@]}"; do
        log_info "Building $pkg..."

        # Find package directory
        PKG_DIR=$(find . -maxdepth 1 -type d -name "${pkg}-*" | head -1)

        if [ -n "$PKG_DIR" ]; then
            cd "$PKG_DIR"

            # Standard build process
            if [ -f "configure" ]; then
                ./configure --prefix=/usr
            elif [ -f "meson.build" ]; then
                meson setup --prefix=/usr build
                cd build
            fi

            make -j$NUM_JOBS
            make install

            cd /sources
        else
            log_warning "Package $pkg not found in sources"
        fi
    done

    log_success "Minimal packages installed"
}

# ============================================================================
# CONFIGURE NETWORKING (Minimal)
# ============================================================================
configure_network() {
    log_info "Configuring minimal networking..."

    # Hostname
    echo "lfs-minimal" > /etc/hostname

    # Hosts file
    cat > /etc/hosts << 'EOF'
127.0.0.1   localhost localhost.localdomain
::1         localhost ip6-localhost ip6-loopback
127.0.1.1   lfs-minimal.localdomain lfs-minimal
EOF

    # Network configuration (using systemd-networkd)
    if command -v systemctl &> /dev/null; then
        mkdir -p /etc/systemd/network

        cat > /etc/systemd/network/20-dhcp.network << 'EOF'
[Match]
Name=en*
Name=eth*

[Network]
DHCP=yes
IPv6PrivacyExtensions=yes
EOF

        systemctl enable systemd-networkd
        systemctl enable systemd-resolved
        ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
    fi

    log_success "Network configured"
}

# ============================================================================
# CONFIGURE SSH (Secure Shell)
# ============================================================================
configure_ssh() {
    log_info "Configuring SSH..."

    # Ensure SSH is installed
    if [ -f /usr/sbin/sshd ]; then
        # Backup original config
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.orig

        # Security hardening for SSH
        cat > /etc/ssh/sshd_config << 'EOF'
# LFS Minimal SSH Configuration
Port 22
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

# Authentication
PermitRootLogin prohibit-password
PubkeyAuthentication yes
PasswordAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes

# Session
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*

# Security
MaxAuthTries 3
MaxSessions 5
ClientAliveInterval 300
ClientAliveCountMax 2
LoginGraceTime 30

# Logging
SyslogFacility AUTH
LogLevel INFO

# Ciphers and MACs (strong encryption)
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256
EOF

        # Generate host keys
        ssh-keygen -A

        # Enable SSH service
        if command -v systemctl &> /dev/null; then
            systemctl enable sshd
        fi

        log_success "SSH configured"
    else
        log_warning "SSH not found, skipping configuration"
    fi
}

# ============================================================================
# CONFIGURE MINIMAL PROFILE
# ============================================================================
configure_minimal_profile() {
    log_info "Configuring minimal system profile..."

    # Create .bashrc for root
    cat >> /root/.bashrc << 'EOF'
# Minimal LFS prompt
PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'

# History
HISTSIZE=1000
HISTFILESIZE=2000
HISTCONTROL=ignoreboth
EOF

    # Create .bashrc for lfsuser
    if [ -d /home/lfsuser ]; then
        cp /root/.bashrc /home/lfsuser/
        chown lfsuser:lfsuser /home/lfsuser/.bashrc
    fi

    # Create motd (message of the day)
    cat > /etc/motd << 'EOF'
===========================================
  LFS Minimal System
  Version: 12.2
  Kernel: $(uname -r)
===========================================
  For help: man LFS
  System info: neofetch
===========================================
EOF

    log_success "Minimal profile configured"
}

# ============================================================================
# INSTALL MINIMAL SYSTEMD SERVICES
# ============================================================================
install_services() {
    log_info "Installing minimal system services..."

    if command -v systemctl &> /dev/null; then
        # Basic services
        systemctl enable systemd-networkd
        systemctl enable systemd-resolved
        systemctl enable systemd-timesyncd
        systemctl enable sshd
        systemctl enable cronie
        systemctl enable rsyslog
        systemctl enable auditd

        # Set target
        systemctl set-default multi-user.target

        log_success "System services enabled"
    fi
}

# ============================================================================
# CREATE LPM REPOSITORY CONFIGURATION
# ============================================================================
configure_lpm() {
    log_info "Configuring LPM package manager..."

    if command -v lpm &> /dev/null; then
        # Add minimal repos
        mkdir -p /etc/lpm/repos.d

        cat > /etc/lpm/repos.d/minimal.repo << 'EOF'
# Minimal repository for LFS
REPO_NAME="minimal"
REPO_URL="https://repos.linuxfromscratch.org/minimal"
REPO_ENABLED="yes"
REPO_PRIORITY="1"
EOF

        log_success "LPM configured"
    fi
}

# ============================================================================
# MINIMAL FILESYSTEM TUNING
# ============================================================================
tune_filesystem() {
    log_info "Tuning filesystem for minimal usage..."

    # Disable unnecessary filesystem features
    cat >> /etc/fstab << 'EOF'
# Minimal fs tuning
# Noatime reduces disk writes
/dev/sda2  /  ext4  defaults,noatime  0  1
EOF

    # Create tmpfs for temporary files
    echo "tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0" >> /etc/fstab
    echo "tmpfs /var/tmp tmpfs defaults,noatime,mode=1777 0 0" >> /etc/fstab

    log_success "Filesystem tuning complete"
}

# ============================================================================
# CLEANUP
# ============================================================================
cleanup() {
    log_info "Cleaning up..."

    # Remove unnecessary files
    rm -rf /usr/share/doc/* 2>/dev/null || true
    rm -rf /usr/share/info/* 2>/dev/null || true
    rm -rf /usr/share/man/* 2>/dev/null || true
    rm -rf /tmp/* 2>/dev/null || true
    rm -rf /var/tmp/* 2>/dev/null || true

    # Strip binaries (reduce size)
    find /usr/bin -type f -exec strip --strip-all {} \; 2>/dev/null || true
    find /usr/lib -type f -exec strip --strip-all {} \; 2>/dev/null || true

    log_success "Cleanup complete"
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    log_info "========================================="
    log_info "LFS Minimal System Installation"
    log_info "========================================="

    install_minimal_packages
    configure_network
    configure_ssh
    configure_minimal_profile
    install_services
    configure_lpm
    tune_filesystem
    cleanup

    log_success "========================================="
    log_success "Minimal System Installation Complete!"
    log_success "========================================="
    echo ""
    echo "Minimal LFS system installed successfully."
    echo ""
    echo "Size: ~1GB"
    echo "Services: SSH, systemd, cron, rsyslog"
    echo ""
    echo "Default login:"
    echo "  Username: lfsuser"
    echo "  Password: lfsuser123"
    echo ""
    echo "To start: reboot"
    echo "========================================="
}

# Run main function
main "$@"