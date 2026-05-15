#!/bin/bash
# Configure desktop environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/utils.sh"

log_info "Configuring desktop environment"

cat > $LFS/configure-desktop.sh << "EOF"
#!/bin/bash

set -e

# Create XFCE configuration for default user
mkdir -p /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/

# Panel configuration
cat > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml << "PANEL"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="panels" type="uint" value="1">
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=6;x=0;y=0"/>
      <property name="length" type="uint" value="100"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/>
        <value type="int" value="2"/>
        <value type="int" value="3"/>
        <value type="int" value="4"/>
        <value type="int" value="5"/>
        <value type="int" value="6"/>
        <value type="int" value="7"/>
        <value type="int" value="8"/>
      </property>
    </property>
  </property>
</channel>
PANEL

# Desktop settings
cat > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml << "DESKTOP"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitor0" type="empty">
        <property name="image-path" type="string" value="/usr/share/backgrounds/default.png"/>
        <property name="image-style" type="int" value="5"/>
      </property>
    </property>
  </property>
</channel>
DESKTOP

# Window manager settings
cat > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml << "XFWM4"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="Default"/>
    <property name="title_font" type="string" value="Sans Bold 9"/>
    <property name="button_layout" type="string" value="O|SHMC"/>
    <property name="button_offset" type="int" value="0"/>
    <property name="easy_click" type="string" value="Alt"/>
    <property name="focus_delay" type="int" value="250"/>
    <property name="focus_hint" type="bool" value="true"/>
    <property name="placement_ratio" type="int" value="20"/>
    <property name="raise_on_focus" type="bool" value="false"/>
    <property name="wrap_windows" type="bool" value="false"/>
    <property name="wrap_workspaces" type="bool" value="false"/>
    <property name="click_to_focus" type="bool" value="true"/>
  </property>
</channel>
XFWM4

# Keyboard shortcuts
cat > /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-keyboard-shortcuts.xml << "SHORTCUTS"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-keyboard-shortcuts" version="1.0">
  <property name="commands" type="empty">
    <property name="default" type="empty">
      <property name="&lt;Primary&gt;&lt;Alt&gt;t" type="empty"/>
      <property name="&lt;Primary&gt;&lt;Alt&gt;Delete" type="empty"/>
      <property name="XF86Display" type="empty"/>
      <property name="&lt;Super&gt;p" type="empty"/>
      <property name="&lt;Primary&gt;Escape" type="empty"/>
      <property name="XF86WWW" type="empty"/>
      <property name="XF86Mail" type="empty"/>
    </property>
  </property>
  <property name="xfwm4" type="empty">
    <property name="default" type="empty">
      <property name="&lt;Alt&gt;F4" type="empty"/>
      <property name="&lt;Alt&gt;F10" type="empty"/>
      <property name="&lt;Alt&gt;F9" type="empty"/>
      <property name="&lt;Alt&gt;F7" type="empty"/>
      <property name="&lt;Alt&gt;F8" type="empty"/>
      <property name="&lt;Alt&gt;Insert" type="empty"/>
      <property name="&lt;Alt&gt;Home" type="empty"/>
    </property>
  </property>
</channel>
SHORTCUTS

# Enable LightDM
systemctl enable lightdm
systemctl set-default graphical.target

# Create default wallpaper directory
mkdir -p /usr/share/backgrounds
cp -f /sources/wallpaper-default.png /usr/share/backgrounds/default.png 2>/dev/null || true

echo "Desktop configuration complete!"
EOF

chmod +x $LFS/configure-desktop.sh

chroot "$LFS" /usr/bin/env -i \
    HOME=/root \
    TERM="$TERM" \
    PS1='(lfs chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin \
    /bin/bash /configure-desktop.sh

log_info "Desktop configuration complete!"