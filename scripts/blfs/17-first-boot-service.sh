#!/bin/bash
# Create first-boot systemd service

cat > /etc/systemd/system/first-boot.service << 'EOF'
[Unit]
Description=First Boot Setup
Before=display-manager.service
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash /usr/local/sbin/first-boot.sh
StandardOutput=journal+console

[Install]
WantedBy=multi-user.target
EOF

# Copy script to destination
cp packages/custom-scripts/first-boot.sh /usr/local/sbin/first-boot.sh
chmod +x /usr/local/sbin/first-boot.sh

# Enable service (will run once, then disable itself)
systemctl enable first-boot.service