#!/bin/bash
# Music Producer Profile Build Script
# CLI-only audio production system

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../common/utils.sh"

log_info "========================================="
log_info "LFS Music Producer Profile Build"
log_info "CLI-only audio production system"
log_info "========================================="

# ============================================================================
# REAL-TIME KERNEL CONFIGURATION
# ============================================================================
configure_rt_kernel() {
    log_info "Configuring real-time kernel for low-latency audio..."

    cd /sources
    if [ -f linux-6.12.20-rt.tar.xz ]; then
        tar -xf linux-6.12.20-rt.tar.xz
        cd linux-6.12.20-rt

        # Enable RT features
        cat >> .config << 'EOF'
# Real-time audio optimizations
CONFIG_PREEMPT_RT=y
CONFIG_HZ_1000=y
CONFIG_HZ=1000
CONFIG_NO_HZ_FULL=y
CONFIG_RCU_BOOST=y
CONFIG_CPU_ISOLATION=y
CONFIG_CPUSETS=y
CONFIG_SCHED_AUTOGROUP=y
CONFIG_IRQ_FORCED_THREADING=y
EOF

        make olddefconfig
        make -j$(nproc)
        make modules_install
        cp arch/x86/boot/bzImage /boot/vmlinuz-lfs-rt
        cp System.map /boot/System.map-rt

        log_success "Real-time kernel installed"
    else
        log_warning "RT kernel not found, using standard kernel"
    fi
}

# ============================================================================
# CONFIGURE AUDIO SYSTEM
# ============================================================================
configure_audio_system() {
    log_info "Configuring audio system for real-time performance..."

    # Add user to audio group
    groupadd -r audio 2>/dev/null || true
    usermod -a -G audio $SUDO_USER 2>/dev/null || true

    # Configure PAM limits for real-time audio
    cat >> /etc/security/limits.conf << 'EOF'
# Real-time audio limits
@audio   -  rtprio     95
@audio   -  memlock    unlimited
@audio   -  nice      -10
EOF

    # Configure sysctl for audio
    cat > /etc/sysctl.d/99-audio.conf << 'EOF'
# Audio performance tuning
vm.swappiness = 10
kernel.sched_rt_runtime_us = 950000
kernel.sched_rt_period_us = 1000000
kernel.msgmax = 65536
kernel.msgmnb = 65536
EOF

    # Create JACK config directory
    mkdir -p /etc/jack

    # JACK configuration (low-latency)
    cat > /etc/jack/jackdrc << 'EOF'
/usr/bin/jackd -d alsa -r 48000 -p 128 -n 3 -P -t 2000
EOF

    # ALSA configuration
    cat > /etc/asound.conf << 'EOF'
# ALSA configuration for low-latency
pcm.!default {
    type plug
    slave.pcm "jack"
    hint.description "Default JACK Audio"
}

pcm.jack {
    type jack
    playback_ports {
        0 system:playback_1
        1 system:playback_2
    }
    capture_ports {
        0 system:capture_1
        1 system:capture_2
    }
}
EOF

    # Create start/stop scripts for audio session
    mkdir -p /usr/local/bin

    cat > /usr/local/bin/start-audio << 'EOF'
#!/bin/bash
# Start real-time audio session

# Start JACK server
jack_control start

# Wait for JACK to be ready
sleep 2

# Start common connections
jack_connect system:capture_1 system:playback_1 2>/dev/null
jack_connect system:capture_2 system:playback_2 2>/dev/null

echo "Audio session started with low-latency (128 frames/period)"
echo "Current latency: $(jack_get_msec_frames 2>/dev/null) ms"
EOF

    cat > /usr/local/bin/stop-audio << 'EOF'
#!/bin/bash
# Stop audio session
jack_control stop
echo "Audio session stopped"
EOF

    chmod 755 /usr/local/bin/start-audio /usr/local/bin/stop-audio

    log_success "Audio system configured"
}

# ============================================================================
# INSTALL SOUNDFONTS
# ============================================================================
install_soundfonts() {
    log_info "Installing default soundfonts..."

    mkdir -p /usr/share/soundfonts

    # Download Fluid GM soundfont (if available)
    if [ -f /sources/FluidR3_GM.sf2 ]; then
        cp /sources/FluidR3_GM.sf2 /usr/share/soundfonts/
    fi

    # Configure FluidSynth to use soundfont
    mkdir -p /etc/fluidsynth
    cat > /etc/fluidsynth/fluidsynth.conf << 'EOF'
# FluidSynth configuration
audio.driver = jack
audio.jack.id = FluidSynth
synth.polyphony = 256
synth.chorus.active = yes
synth.reverb.active = yes
shell.port = 9988
player.port = 9989
EOF

    # Auto-load soundfont
    if [ -f /usr/share/soundfonts/FluidR3_GM.sf2 ]; then
        echo "synth.soundfont = /usr/share/soundfonts/FluidR3_GM.sf2" >> /etc/fluidsynth/fluidsynth.conf
    fi

    log_success "Soundfonts installed"
}

# ============================================================================
# CREATE DEMO PROJECT
# ============================================================================
create_demo_project() {
    log_info "Creating demo project structure..."

    mkdir -p /home/$SUDO_USER/music-projects/demo
    cd /home/$SUDO_USER/music-projects/demo

    # Create simple shell script to generate test tone
    cat > test-tone.sh << 'EOF'
#!/bin/bash
# Generate test tone with SoX
sox -n output.wav synth 10 sin 440 vol 0.8
echo "Generated 440Hz test tone (10 seconds)"
EOF
    chmod +x test-tone.sh

    # Create MIDI demo file
    cat > demo-midi.sh << 'EOF'
#!/bin/bash
# Create a simple MIDI demo
echo "Creating MIDI demo..."
echo "MThd 0 1 96" > demo.mid
echo "MTrk 0 96" >> demo.mid
for note in 60 64 67 72; do
    echo "Mid Note 0 $note 100 96" >> demo.mid
    echo "Mid Note 0 0 0 96" >> demo.mid
done
echo "TrkEnd" >> demo.mid
echo "MIDI file created: demo.mid"
echo "Play with: fluidsynth /usr/share/soundfonts/FluidR3_GM.sf2 demo.mid"
EOF
    chmod +x demo-midi.sh

    chown -R $SUDO_USER:$SUDO_USER /home/$SUDO_USER/music-projects

    log_success "Demo project created"
}

# ============================================================================
# CREATE PROFILE SPECIFIC ALIASES
# ============================================================================
configure_profile_aliases() {
    log_info "Configuring music producer aliases..."

    cat >> /home/$SUDO_USER/.bashrc << 'EOF'

# ============================================================================
# Music Producer Aliases
# ============================================================================

# Audio system
alias jack-start='jack_control start'
alias jack-stop='jack_control stop'
alias jack-status='jack_control status'
alias audio-start='start-audio'
alias audio-stop='stop-audio'

# JACK utilities
alias jack-ls='jack_lsp'
alias jack-connect='jack_connect'
alias jack-disconnect='jack_disconnect'
alias jack-midi='aconnect -l'

# MIDI utilities
alias midi-ls='aconnect -l'
alias midi-connect='aconnect'
alias fluidsynth-start='fluidsynth -a jack -g 0.5 /usr/share/soundfonts/FluidR3_GM.sf2 &'
alias timidity-play='timidity -Ow'

# Audio conversion
alias wav2mp3='lame -h -V2'
alias wav2flac='flac -8'
alias mp32wav='lame --decode'
alias flac2wav='flac -d'

# Audio info
alias audio-info='sox --info'
alias midi-info='midicsv'
alias playback='aplay'
alias record='arecord'

# Project directories
alias cd-projects='cd ~/music-projects'
alias cd-demo='cd ~/music-projects/demo'

# System tweaks
alias rt-status='cat /proc/sys/kernel/sched_rt_runtime_us'
alias audio-limits='ulimit -a | grep -E "rtprio|nice|memlock"'
EOF

    chown $SUDO_USER:$SUDO_USER /home/$SUDO_USER/.bashrc

    log_success "Profile aliases configured"
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    configure_rt_kernel
    configure_audio_system
    install_soundfonts
    create_demo_project
    configure_profile_aliases

    log_success "========================================="
    log_success "Music Producer Profile Installation Complete!"
    log_success "========================================="
    echo ""
    echo "Commands available after boot:"
    echo "  start-audio      : Start JACK with low-latency"
    echo "  stop-audio       : Stop audio session"
    echo "  jack-ls          : List JACK ports"
    echo "  midi-ls          : List MIDI connections"
    echo "  cd-projects      : Go to projects directory"
    echo ""
    echo "Real-time priority granted to 'audio' group"
    echo "Current user added to audio group"
    echo ""
    echo "To test audio:"
    echo "  start-audio"
    echo "  fluidsynth /usr/share/soundfonts/FluidR3_GM.sf2 demo.mid"
    echo ""
}

main "$@"