#!/bin/bash
# Configure desktop - Docker compatible minimal
set -e
LFS=${LFS:-/output/image}
echo "[INFO] Configuring desktop (Docker mode)"
mkdir -pv $LFS/etc/skel/.config/xfce4
mkdir -pv $LFS/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml
# Create default panel config
cat > $LFS/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml << 'PANEL'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=6;x=0;y=0"/>
      <property name="length" type="uint" value="100"/>
      <property name="size" type="uint" value="48"/>
      <property name="plugins" type="array">
        <value type="string" value="whiskermenu"/>
        <value type="string" value="tasklist"/>
        <value type="string" value="systray"/>
        <value type="string" value="pulseaudio"/>
        <value type="string" value="clock"/>
      </property>
    </property>
  </property>
</channel>
PANEL
echo "[SUCCESS] Desktop configuration skeleton created"
exit 0
