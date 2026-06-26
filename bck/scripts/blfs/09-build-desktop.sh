#!/bin/bash
# Desktop environment - Docker compatible minimal
set -e
LFS=${LFS:-/output/image}
echo "[INFO] Setting up desktop environment (Docker mode)"

# Créer tous les répertoires nécessaires
mkdir -pv $LFS/etc/X11/xorg.conf.d
mkdir -pv $LFS/etc/xdg/xfce4/xfconf/xfce-perchannel-xml
mkdir -pv $LFS/etc/xdg/autostart
mkdir -pv $LFS/usr/share/xfce4
mkdir -pv $LFS/usr/share/applications

# Créer un fichier de configuration XFCE minimal
cat > $LFS/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml << 'SESSION'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-session" version="1.0">
  <property name="general" type="empty">
    <property name="FailsafeSession" type="string" value="Failsafe"/>
    <property name="SessionName" type="string" value="Default"/>
  </property>
</channel>
SESSION

echo "[SUCCESS] Desktop environment skeleton created"
exit 0
