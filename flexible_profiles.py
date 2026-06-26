#!/usr/bin/env python3
"""
FlexibleProfileManager - Extended profile manager with configuration options
Allows users to customize desktop, init system, and audio for each profile
"""

import sys
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent))

from profiles_config import PROFILES_CONFIG, PROFILE_TEMPLATES


class FlexibleProfileManager:
    """
    Extended ProfileManager that supports flexible configuration of:
    - Desktop environments (xfce, gnome, kde, lxqt, none)
    - Init systems (sysvinit, systemd, openrc, runit, s6)
    - Audio modes (none, cli, studio)
    """

    def __init__(self):
        self.profiles = PROFILES_CONFIG
        self.templates = PROFILE_TEMPLATES

    def get_profile(self, name: str):
        """Get base profile"""
        if name not in self.profiles:
            raise ValueError(f"Unknown profile: {name}")
        return self.profiles[name]

    def customize_profile(self, profile_name: str, desktop=None, init_system=None, audio=None):
        """
        Customize a profile with specific desktop, init system, and audio options

        Returns: Customized profile dictionary
        """
        profile = self.get_profile(profile_name).copy()

        # Validate and apply desktop choice
        if desktop:
            if desktop not in profile.get('desktop_options', []):
                raise ValueError(
                    f"Desktop '{desktop}' not available for profile '{profile_name}'. "
                    f"Choose from: {', '.join(profile.get('desktop_options', []))}"
                )
            profile['desktop'] = desktop

        # Validate and apply init system choice
        if init_system:
            if init_system not in profile.get('init_options', []):
                raise ValueError(
                    f"Init system '{init_system}' not available for profile '{profile_name}'. "
                    f"Choose from: {', '.join(profile.get('init_options', []))}"
                )
            profile['init_system'] = init_system

        # Validate and apply audio choice
        if audio:
            if audio not in profile.get('audio_options', []):
                raise ValueError(
                    f"Audio mode '{audio}' not available for profile '{profile_name}'. "
                    f"Choose from: {', '.join(profile.get('audio_options', []))}"
                )
            profile['audio'] = audio

        return profile

    def list_profiles(self):
        """List all available profiles"""
        return list(self.profiles.keys())

    def get_profile_info(self, name: str, desktop=None, init_system=None, audio=None) -> str:
        """Get detailed profile information with customization"""
        profile = self.customize_profile(name, desktop, init_system, audio)

        return f"""
╔══════════════════════════════════════════════════════════════════╗
║ Profile: {name.upper()}
╠══════════════════════════════════════════════════════════════════╣
║ Description:   {profile['description']}
║ Size:          ~{profile['size_gb']} GB
║ Build time:    ~{profile['build_time_hours']} hours
║
║ Configuration:
║   Desktop:     {profile['desktop']} (options: {', '.join(profile.get('desktop_options', []))})
║   Init System: {profile['init_system']} (options: {', '.join(profile.get('init_options', []))})
║   Audio:       {profile['audio']} (options: {', '.join(profile.get('audio_options', []))})
║
║ Features:
║   Java Dev:    {'✓' if profile['java_dev'] else '✗'}
║   Package Mgr: {'✓' if profile['package_manager'] else '✗'}
║   Security:    {'✓' if profile.get('security_hardening', False) else '✗'}
║   Privacy:     {'✓' if profile.get('privacy_tools', False) else '✗'}
║   Live USB:    {'✓' if profile.get('live_system', False) else '✗'}
║   Updates:     {'✓' if profile.get('system_updater', False) else '✗'}
╚══════════════════════════════════════════════════════════════════╝
"""

    def show_customization_guide(self, profile_name: str) -> str:
        """Show how to customize a profile"""
        profile = self.get_profile(profile_name)

        guide = f"""
╔══════════════════════════════════════════════════════════════════╗
║ {profile_name.upper()} - Customization Guide
╠══════════════════════════════════════════════════════════════════╣

Choose your desktop environment:
"""
        for desktop in profile.get('desktop_options', []):
            guide += f"  python3 builder.py --profile {profile_name} --desktop {desktop}\n"

        guide += "\nChoose your init system:\n"
        for init_sys in profile.get('init_options', []):
            guide += f"  python3 builder.py --profile {profile_name} --init {init_sys}\n"

        guide += "\nChoose your audio setup:\n"
        for audio in profile.get('audio_options', []):
            guide += f"  python3 builder.py --profile {profile_name} --audio {audio}\n"

        guide += "\nCombine options:\n"
        guide += f"  python3 builder.py --profile {profile_name} --desktop xfce --init systemd --audio studio\n"

        guide += """
╚══════════════════════════════════════════════════════════════════╝
"""
        return guide

    def validate_build_config(self, profile_name: str, desktop=None, init_system=None, audio=None) -> bool:
        """Validate if the build configuration is compatible"""
        try:
            self.customize_profile(profile_name, desktop, init_system, audio)
            return True
        except ValueError:
            return False

    def get_size_estimate(self, profile_name: str, audio=None) -> float:
        """Get estimated size with audio considerations"""
        profile = self.get_profile(profile_name)
        base_size = profile['size_gb']

        if audio == 'cli':
            base_size += 1  # CLI audio is smaller
        elif audio == 'studio':
            base_size += 3  # Studio audio adds DAWs and plugins

        return base_size

    def get_time_estimate(self, profile_name: str, audio=None) -> float:
        """Get estimated build time with audio considerations"""
        profile = self.get_profile(profile_name)
        base_time = profile['build_time_hours']

        if audio == 'cli':
            base_time += 0.5  # CLI audio is quick
        elif audio == 'studio':
            base_time += 2    # Studio audio takes longer

        return base_time


# Example usage and testing
if __name__ == '__main__':
    manager = FlexibleProfileManager()

    print("=" * 70)
    print("FLEXIBLE PROFILE MANAGER - EXAMPLES")
    print("=" * 70)

    # Example 1: Get profile info with customization
    print("\n✓ Example 1: XFCE with custom options")
    print(manager.get_profile_info('xfce', desktop='lxqt', init_system='openrc', audio='cli'))

    # Example 2: Show customization guide
    print("\n✓ Example 2: Customization guide for audio-cli profile")
    print(manager.show_customization_guide('audio-cli'))

    # Example 3: Size estimates
    print("\n✓ Example 3: Size estimates with audio options")
    for audio in ['none', 'cli', 'studio']:
        size = manager.get_size_estimate('gnome', audio=audio)
        time = manager.get_time_estimate('gnome', audio=audio)
        print(f"  GNOME + {audio:6s} audio: {size:.1f}GB, ~{time}h build time")

    # Example 4: Validate configurations
    print("\n✓ Example 4: Validate configurations")
    test_cases = [
        ('xfce', 'xfce', 'systemd', None),
        ('xfce', 'kde', 'systemd', None),    # Should fail - kde not in xfce options
        ('audio-cli', 'none', None, 'cli'),
        ('full', 'gnome', 'openrc', 'studio'),
    ]

    for profile_name, desktop, init_sys, audio in test_cases:
        try:
            result = manager.validate_build_config(profile_name, desktop, init_sys, audio)
            status = "✓ Valid" if result else "✗ Invalid"
            print(f"  {status}: {profile_name} with {desktop}/{init_sys}/{audio}")
        except ValueError as e:
            print(f"  ✗ Invalid: {e}")

    print("\n" + "=" * 70)
    print("All examples completed!")
    print("=" * 70)

