#!/bin/bash
# Post-installation customization

set -e

log_info "Running post-installation scripts"

# Install additional fonts
mkdir -p /usr/share/fonts/TTF
cd /sources
wget https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/CascadiaCode.zip
unzip CascadiaCode.zip -d /usr/share/fonts/TTF/
fc-cache -fv

# Configure bash prompt
cat >> /etc/bash.bashrc << "BASH"
# Custom prompt
PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

# Aliases
alias ls='ls --color=auto'
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'

# History
HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoreboth
BASH

# Configure Vim
cat > /etc/vimrc << "VIM"
set number
set relativenumber
set tabstop=4
set shiftwidth=4
set expandtab
set mouse=a
syntax on
VIM

# Install some useful scripts
cat > /usr/local/bin/welcome.sh << "WELCOME"
#!/bin/bash
clear
echo "========================================="
echo "   Welcome to LFS Linux Desktop"
echo "========================================="
echo "  Distribution: LFS $(cat /etc/lfs-release)"
echo "  Kernel: $(uname -r)"
echo "  Desktop: $(cat /etc/desktop-environment)"
echo "========================================="
echo ""
WELCOME

chmod +x /usr/local/bin/welcome.sh

# Add welcome message to profile
echo "/usr/local/bin/welcome.sh" >> /etc/profile

echo "Post-installation complete!"