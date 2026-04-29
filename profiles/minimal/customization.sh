#!/bin/bash
# Minimal profile - no desktop

set -e

log_info "Applying minimal profile (no desktop)"

# No desktop, just console
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << "EOF"
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I $TERM
EOF

echo "Minimal profile applied"