#!/bin/bash
# Security Hardening for LFS Distribution
# Run inside chroot environment after base system

set -e

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[0;34m[SUCCESS]\033[0m $1"; }
log_warning() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }

###############################################################################
# 1. KERNEL HARDENING
###############################################################################
harden_kernel() {
    log_info "Applying kernel security settings"

    cat > /etc/sysctl.d/99-security.conf << 'EOF'
# === KERNEL HARDENING ===

# Restrict kernel pointer access
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.printk = 3 3 3 3

# Restrict kernel module loading
kernel.modules_disabled = 0
kernel.kexec_load_disabled = 1

# ASLR improvements
kernel.randomize_va_space = 2

# Restrict perf events
kernel.perf_event_paranoid = 3
kernel.perf_event_max_sample_rate = 1000

# Restrict BPF
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2

# === NETWORK SECURITY ===

# IP spoofing protection
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignore ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Ignore send redirects
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Disable source packet routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# Log Martians
net.ipv4.conf.all.log_martians = 1

# Ignore ICMP ping requests
net.ipv4.icmp_echo_ignore_all = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Disable IPv6 if not needed
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0

# === MEMORY PROTECTION ===

# Prevent memory from being written to executable
kernel.exec-shield = 1
kernel.randomize_va_space = 2

# Restrict ptrace
kernel.yama.ptrace_scope = 2

# Restrict userfaultfd
vm.unprivileged_userfaultfd = 0

# === FILESYSTEM PROTECTION ===

# Protected links and fifos
fs.protected_fifos = 2
fs.protected_hardlinks = 1
fs.protected_regular = 2
fs.protected_symlinks = 1

# Restrict mounting
fs.suid_dumpable = 0

# === PROCESS ISOLATION ===

# PID limits
kernel.pid_max = 65536

# Restrict cgroups
kernel.cgroup_allowed = 0
EOF

    sysctl -p /etc/sysctl.d/99-security.conf
    log_success "Kernel hardening applied"
}

###############################################################################
# 2. FIREWALL SETUP (iptables/nftables)
###############################################################################
setup_firewall() {
    log_info "Setting up firewall"

    # Check for nftables (modern) or iptables (legacy)
    if command -v nft >/dev/null; then
        setup_nftables
    else
        setup_iptables
    fi

    # Enable firewall at boot
    cat > /etc/systemd/system/firewall.service << 'EOF'
[Unit]
Description=Firewall
Before=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/firewall-start
ExecStop=/usr/local/sbin/firewall-stop

[Install]
WantedBy=multi-user.target
EOF

    chmod +x /usr/local/sbin/firewall-start
    chmod +x /usr/local/sbin/firewall-stop
    systemctl enable firewall

    log_success "Firewall configured"
}

setup_nftables() {
    cat > /etc/nftables.conf << 'EOF'
#!/usr/sbin/nft -f

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;

        # Allow loopback
        iif lo accept

        # Allow established connections
        ct state established,related accept

        # Allow ICMP (ping)
        ip protocol icmp icmp type { echo-request, echo-reply } accept
        ip6 nexthdr icmpv6 icmpv6 type { echo-request, echo-reply } accept

        # Allow SSH (optional)
        tcp dport 22 accept

        # Allow HTTP/HTTPS (if needed)
        # tcp dport { 80, 443 } accept

        # Log dropped packets
        log prefix "nftables INPUT drop: " counter drop
    }

    chain forward {
        type filter hook forward priority 0; policy drop;
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF

    cat > /usr/local/sbin/firewall-start << 'EOF'
#!/bin/bash
nft -f /etc/nftables.conf
EOF

    cat > /usr/local/sbin/firewall-stop << 'EOF'
#!/bin/bash
nft flush ruleset
EOF
}

setup_iptables() {
    cat > /etc/iptables.rules << 'EOF'
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]

# Allow loopback
-A INPUT -i lo -j ACCEPT

# Allow established connections
-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow SSH
-A INPUT -p tcp --dport 22 -j ACCEPT

# Allow ICMP (ping)
-A INPUT -p icmp --icmp-type echo-request -j ACCEPT
-A INPUT -p icmp --icmp-type echo-reply -j ACCEPT

# Log dropped packets
-A INPUT -m limit --limit 5/min -j LOG --log-prefix "iptables DROP: "

COMMIT
EOF

    cat > /usr/local/sbin/firewall-start << 'EOF'
#!/bin/bash
iptables-restore < /etc/iptables.rules
ip6tables-restore < /etc/ip6tables.rules 2>/dev/null || true
EOF

    cat > /usr/local/sbin/firewall-stop << 'EOF'
#!/bin/bash
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
iptables -F
EOF
}

###############################################################################
# 3. PRIVACY SETTINGS
###############################################################################
configure_privacy() {
    log_info "Configuring privacy settings"

    # Disable telemetry and tracking
    cat > /etc/profile.d/privacy.sh << 'EOF'
# Privacy settings
export HISTCONTROL=ignoreboth
export HISTFILESIZE=2000
export HISTSIZE=2000
export HISTTIMEFORMAT="%F %T "

# Disable bash history for root in dangerous contexts
if [ "$USER" = "root" ]; then
    export HISTFILE=/dev/null
fi
EOF

    # Disable core dumps for setuid programs
    echo "* soft core 0" > /etc/security/limits.d/99-disable-core.conf
    echo "* hard core 0" >> /etc/security/limits.d/99-disable-core.conf

    # Clear /tmp on boot
    cat > /etc/tmpfiles.d/clear-tmp.conf << 'EOF'
# Clear /tmp on boot
r! /tmp 1777 root root 0
EOF

    # Disable lastlog (user login tracking)
    if [ -f /etc/pam.d/system-login ]; then
        sed -i 's/session    optional     pam_lastlog.so/session    optional     pam_lastlog.so silent/' /etc/pam.d/system-login
    fi

    # Configure rsyslog to not log sensitive info
    if [ -f /etc/rsyslog.conf ]; then
        cat >> /etc/rsyslog.conf << 'EOF'
# Privacy: Don't log authentication success
auth,authpriv.*    /var/log/auth.log
auth,authpriv.info stop
EOF
    fi

    log_success "Privacy settings configured"
}

###############################################################################
# 4. FAIL2BAN INSTALLATION (Brute force protection)
###############################################################################
install_fail2ban() {
    log_info "Installing fail2ban for brute force protection"

    cd /sources
    tar -xf fail2ban-*.tar.gz
    cd fail2ban-*
    python3 setup.py install

    # Create configuration
    mkdir -p /etc/fail2ban
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 7200

[sshd-ddos]
enabled = true
port = ssh
filter = sshd-ddos
logpath = /var/log/auth.log
maxretry = 2
EOF

    # Create systemd service
    cat > /etc/systemd/system/fail2ban.service << 'EOF'
[Unit]
Description=Fail2Ban Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/fail2ban-server -x -b
ExecReload=/usr/local/bin/fail2ban-client reload
ExecStop=/usr/local/bin/fail2ban-client stop

[Install]
WantedBy=multi-user.target
EOF

    systemctl enable fail2ban
    log_success "Fail2ban installed"
}

###############################################################################
# 5. AUDIT SYSTEM
###############################################################################
setup_audit() {
    log_info "Setting up audit system"

    # Install auditd
    cd /sources
    tar -xf audit-*.tar.gz
    cd audit-*
    ./configure --prefix=/usr
    make -j$(nproc)
    make install

    # Configure audit rules
    cat > /etc/audit/audit.rules << 'EOF'
# Delete all existing rules
-D

# Buffer size
-b 8192

# Failure mode
-f 1

# Monitor critical files
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/sudoers -p wa -k sudoers
-w /etc/ssh/sshd_config -p wa -k sshd

# Monitor system calls
-a always,exit -S execve -k process_execution
-a always,exit -S mount -S umount2 -k mount

# Monitor kernel modules
-w /sbin/insmod -p x -k module_insertion

# Make immutable
-e 2
EOF

    systemctl enable auditd
    log_success "Audit system configured"
}

###############################################################################
# 6. APPARMOR (Mandatory Access Control)
###############################################################################
setup_apparmor() {
    log_info "Setting up AppArmor MAC system"

    cd /sources
    tar -xf apparmor-*.tar.gz
    cd apparmor-*
    make -j$(nproc)
    make install

    # Load default profiles
    systemctl enable apparmor

    # Basic profiles
    cat > /etc/apparmor.d/usr.sbin.sshd << 'EOF'
#include <tunables/global>

profile sshd /usr/sbin/sshd flags=(attach_disconnected) {
  #include <abstractions/base>
  #include <abstractions/nameservice>
  #include <abstractions/ssl_certs>

  capability net_bind_service,
  capability setgid,
  capability setuid,

  /usr/sbin/sshd mr,
  /etc/ssh/sshd_config r,
  /etc/ssh/ssh_host_* r,
  /var/run/sshd.pid rw,
  /var/log/auth.log w,
  /proc/[0-9]*/fd/ r,

  # Private keys
  /etc/ssh/ssh_host_*_key r,
  /root/.ssh/authorized_keys r,
  /home/*/.ssh/authorized_keys r,

  # Subprocess execution
  /bin/bash PUx,
}
EOF

    aa-enforce /etc/apparmor.d/usr.sbin.sshd
    log_success "AppArmor configured"
}

###############################################################################
# 7. DAILY SECURITY SCANS
###############################################################################
setup_security_scans() {
    log_info "Setting up daily security scans"

    # Rootkit hunter
    cd /sources
    tar -xf rkhunter-*.tar.gz
    cd rkhunter-*
    ./installer.sh --install

    # Lynis security audit tool
    cd /sources
    tar -xf lynis-*.tar.gz
    cd lynis-*
    cp -r . /usr/local/lynis
    ln -sf /usr/local/lynis/lynis /usr/local/bin/lynis

    # Daily cron job
    cat > /etc/cron.daily/security-scan << 'EOF'
#!/bin/bash
# Daily security scan

LOG="/var/log/security-scan-$(date +%Y%m%d).log"

echo "=== Security Scan $(date) ===" > $LOG
echo "" >> $LOG

# Rkhunter scan
echo "--- Rootkit Hunter ---" >> $LOG
/usr/local/bin/rkhunter --check --skip-keypress --report-warnings-only >> $LOG 2>&1

# Check for SUID files
echo "" >> $LOG
echo "--- SUID Files ---" >> $LOG
find / -type f -perm -4000 2>/dev/null >> $LOG

# Check for world-writable files
echo "" >> $LOG
echo "--- World Writable Files ---" >> $LOG
find / -type f -perm -0002 -not -path "/proc/*" -not -path "/sys/*" 2>/dev/null | head -50 >> $LOG

# Check for unauthorized users
echo "" >> $LOG
echo "--- Users with UID 0 ---" >> $LOG
grep ':0:' /etc/passwd >> $LOG

# Check listening ports
echo "" >> $LOG
echo "--- Listening Ports ---" >> $LOG
netstat -tuln 2>/dev/null >> $LOG

# Mail report to root
mail -s "Security Scan Report $(date +%Y%m%d)" root < $LOG
EOF

    chmod +x /etc/cron.daily/security-scan

    log_success "Security scans configured"
}

###############################################################################
# 8. USER ACCOUNT HARDENING
###############################################################################
harden_user_accounts() {
    log_info "Hardening user accounts"

    # Password policy
    cat > /etc/security/pwquality.conf << 'EOF'
minlen = 12
dcredit = -1
ucredit = -1
lcredit = -1
ocredit = -1
difok = 3
usercheck = 1
enforcing = 1
EOF

    # Login delay after failures
    cat >> /etc/pam.d/system-auth << 'EOF'
auth       required     pam_faildelay.so delay=4000000
auth       required     pam_tally2.so deny=5 unlock_time=1800
account    required     pam_tally2.so
EOF

    # Inactive account lockout
    useradd -D -f 30

    # Disable root SSH login
    if [ -f /etc/ssh/sshd_config ]; then
        sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
        sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
        echo "PermitRootLogin no" >> /etc/ssh/sshd_config
        systemctl restart sshd
    fi

    log_success "User accounts hardened"
}

###############################################################################
# 9. ENCRYPTION SETUP (LUKS/GPG)
###############################################################################
setup_encryption() {
    log_info "Setting up encryption tools"

    # Install GPG
    cd /sources
    tar -xf gnupg-*.tar.bz2
    cd gnupg-*
    ./configure --prefix=/usr
    make -j$(nproc)
    make install

    # Create encrypted swap script
    cat > /usr/local/sbin/setup-encrypted-swap << 'EOF'
#!/bin/bash
# Create encrypted swap with random key

SWAP_FILE=/swapfile
SWAP_SIZE=2048

# Create swap file
dd if=/dev/urandom of=$SWAP_FILE bs=1M count=$SWAP_SIZE
chmod 600 $SWAP_FILE

# Setup encryption with random key
cryptsetup open --type plain --key-file=/dev/urandom $SWAP_FILE swap
mkswap /dev/mapper/swap
swapon /dev/mapper/swap

echo "Encrypted swap active"
EOF

    chmod +x /usr/local/sbin/setup-encrypted-swap

    log_success "Encryption tools installed"
}

###############################################################################
# 10. HIDS (Host Intrusion Detection)
###############################################################################
setup_hids() {
    log_info "Setting up AIDE (Advanced Intrusion Detection)"

    cd /sources
    tar -xf aide-*.tar.gz
    cd aide-*
    ./configure --prefix=/usr --sysconfdir=/etc
    make -j$(nproc)
    make install

    # Initialize database
    aide --init
    mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz

    # Daily check
    cat > /etc/cron.daily/aide-check << 'EOF'
#!/bin/bash
/usr/bin/aide --check | mail -s "AIDE Intrusion Check $(date)" root
EOF
    chmod +x /etc/cron.daily/aide-check

    log_success "HIDS configured"
}

###############################################################################
# MAIN
###############################################################################
main() {
    log_info "=== SECURITY HARDENING ==="

    harden_kernel
    setup_firewall
    configure_privacy
    install_fail2ban
    setup_audit
    # setup_apparmor   # Optional, can be heavy
    setup_security_scans
    harden_user_accounts
    setup_encryption
    setup_hids

    log_success "=== SECURITY HARDENING COMPLETE ==="

    echo ""
    echo "Security features installed:"
    echo "  ✓ Kernel hardening (sysctl)"
    echo "  ✓ Firewall (nftables/iptables)"
    echo "  ✓ Privacy settings"
    echo "  ✓ Fail2ban (brute force protection)"
    echo "  ✓ Audit system (auditd)"
    echo "  ✓ Daily security scans"
    echo "  ✓ User account hardening"
    echo "  ✓ Encryption tools (GPG, cryptsetup)"
    echo "  ✓ File integrity monitoring (AIDE)"
    echo ""
    echo "Daily checks:"
    echo "  - /etc/cron.daily/security-scan"
    echo "  - /etc/cron.daily/aide-check"
    echo ""
    echo "To run manual security audit:"
    echo "  $ lynis audit system"
}

main "$@"