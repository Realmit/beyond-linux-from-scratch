#!/usr/bin/env python3
"""
LFS URL Report Analyzer
Analyzes validation results and provides fixes for broken URLs
"""

import json
import re
from pathlib import Path
from datetime import datetime
from collections import defaultdict
from typing import Dict, List, Tuple, Optional
import urllib.parse

class URLAnalyzer:
    """Analyze URL validation results and provide fixes"""

    # Known working URL patterns and their fixes
    FIX_PATTERNS = {
        # GNU FTP - use specific mirrors or known working versions
        r'ftp\.gnu\.org/gnu/([^/]+)/([^/]+)\.tar\.(gz|xz|bz2)': {
            'mirror': 'https://mirrors.kernel.org/gnu/{package}/{filename}',
            'alternative': 'https://ftp.gnu.org/gnu/{package}/',
            'note': 'Try version without -rc or -pre'
        },
        # Apache - need to check latest versions
        r'dlcdn\.apache\.org/([^/]+)/([^/]+)/([^/]+)': {
            'note': 'Check https://dlcdn.apache.org/{category}/ for latest versions'
        },
        # GitHub - fix tag/archive URLs
        r'github\.com/([^/]+)/([^/]+)/archive/refs/tags/([^/]+)\.tar\.gz': {
            'fix': 'https://github.com/{user}/{repo}/archive/refs/tags/{tag}.tar.gz',
            'note': 'Check if tag exists or use main/master branch'
        },
        # GNOME - version patterns
        r'download\.gnome\.org/sources/([^/]+)/([0-9]+\.[0-9]+)/([^/]+)\.tar\.xz': {
            'note': 'Check https://download.gnome.org/sources/{package}/ for available versions'
        },
    }

    # Common version patterns and their fixes
    VERSION_FIXES = {
        'glibc': {
            'latest': '2.44',
            'stable': '2.43',
            'url': 'https://ftp.gnu.org/gnu/glibc/glibc-{version}.tar.xz'
        },
        'gcc': {
            'latest': '15.2.0',
            'stable': '15.1.0',
            'url': 'https://ftp.gnu.org/gnu/gcc/gcc-{version}/gcc-{version}.tar.xz'
        },
        'binutils': {
            'latest': '2.46.0',
            'stable': '2.45.0',
            'url': 'https://ftp.gnu.org/gnu/binutils/binutils-{version}.tar.xz'
        },
        'make': {
            'latest': '4.4.1',
            'stable': '4.4',
            'url': 'https://ftp.gnu.org/gnu/make/make-{version}.tar.gz'
        },
        'bash': {
            'latest': '5.3',
            'stable': '5.2.37',
            'url': 'https://ftp.gnu.org/gnu/bash/bash-{version}.tar.gz'
        },
        'linux': {
            'latest': '6.14.8',
            'stable': '6.12.20',
            'url': 'https://www.kernel.org/pub/linux/kernel/v6.x/linux-{version}.tar.xz'
        },
        'maven': {
            'latest': '3.9.9',
            'stable': '3.9.8',
            'url': 'https://dlcdn.apache.org/maven/maven-3/{version}/binaries/apache-maven-{version}-bin.tar.gz'
        },
        'tomcat': {
            'latest': '10.1.39',
            'stable': '10.1.38',
            'url': 'https://dlcdn.apache.org/tomcat/tomcat-10/v{version}/bin/apache-tomcat-{version}.tar.gz'
        },
        'gradle': {
            'latest': '8.15',
            'stable': '8.14',
            'url': 'https://services.gradle.org/distributions/gradle-{version}-bin.zip'
        }
    }

    def __init__(self, report_file: Path = Path('packages/sources_report.json')):
        self.report_file = report_file
        self.data = self.load_report()
        self.invalid_urls = self.get_invalid_urls()
        self.fixes = {}
        self.suggestions = defaultdict(list)

    def load_report(self) -> Dict:
        """Load the JSON report"""
        if not self.report_file.exists():
            print(f" Report file not found: {self.report_file}")
            return {}

        with open(self.report_file) as f:
            return json.load(f)

    def get_invalid_urls(self) -> List[Dict]:
        """Extract invalid URLs from report"""
        return [r for r in self.data.get('results', []) if r.get('valid') is False]

    def analyze_url(self, url: str, message: str) -> Dict:
        """Analyze a single URL and suggest fixes"""
        result = {
            'url': url,
            'error': message,
            'fix': None,
            'note': None,
            'status': 'needs_manual'
        }

        # Check if it's a GNU FTP timeout
        if 'ftp.gnu.org' in url and 'TIMEOUT' in message:
            result['status'] = 'timeout'
            result['note'] = 'GNU FTP server is slow. Try using a mirror or increasing timeout.'

            # Extract package name
            match = re.search(r'ftp\.gnu\.org/gnu/([^/]+)/', url)
            if match:
                package = match.group(1)
                if package in self.VERSION_FIXES:
                    version = self.VERSION_FIXES[package]['latest']
                    result['fix'] = self.VERSION_FIXES[package]['url'].format(version=version)
                    result['note'] = f"Try version {version} or check for newer versions"
                    result['status'] = 'version_mismatch'

        # Check for 404 errors
        elif '404' in message:
            result['status'] = 'not_found'

            # GitHub archive URL
            if 'github.com' in url and 'archive/refs/tags' in url:
                match = re.search(r'github\.com/([^/]+)/([^/]+)/archive/refs/tags/([^/]+)', url)
                if match:
                    user, repo, tag = match.groups()
                    result['note'] = f"Check if tag '{tag}' exists at https://github.com/{user}/{repo}/releases"
                    result['fix'] = f"https://github.com/{user}/{repo}/archive/refs/heads/main.tar.gz"
                    result['status'] = 'github_tag_mismatch'

            # Apache download
            elif 'dlcdn.apache.org' in url:
                match = re.search(r'dlcdn\.apache\.org/([^/]+)/([^/]+)', url)
                if match:
                    category, version = match.groups()
                    result['note'] = f"Check for newer versions at https://dlcdn.apache.org/{category}/"
                    result['status'] = 'apache_version_mismatch'

            # GNOME download
            elif 'download.gnome.org' in url:
                match = re.search(r'download\.gnome\.org/sources/([^/]+)/([0-9.]+)', url)
                if match:
                    package, version = match.groups()
                    major = '.'.join(version.split('.')[:2])
                    result['note'] = f"Check for newer versions at https://download.gnome.org/sources/{package}/{major}/"
                    result['status'] = 'gnome_version_mismatch'

            # SourceForge
            elif 'sourceforge.net' in url or 'downloads.sourceforge.net' in url:
                result['note'] = "SourceForge URLs may be blocked. Try using the project's official website."
                result['status'] = 'sourceforge_issue'

        # Connection refused
        elif 'CONNECTION REFUSED' in message:
            result['status'] = 'connection_refused'
            result['note'] = "The server is unreachable. Try using HTTPS or a different mirror."

        # SSL errors
        elif 'SSL' in message or 'CERTIFICATE' in message:
            result['status'] = 'ssl_error'
            result['note'] = "SSL certificate error. Try using HTTP or updating your SSL certificates."
            if 'ftp.mutt.org' in url:
                result['fix'] = url.replace('https://', 'http://')

        # HTTP 418 (Teapot)
        elif '418' in message:
            result['status'] = 'blocked'
            result['note'] = "Server returned 418 - you've been blocked. Try using a different mirror."

        return result

    def analyze_all(self) -> Dict:
        """Analyze all invalid URLs"""
        results = {}

        for entry in self.invalid_urls:
            url = entry['url']
            message = entry.get('message', 'Unknown error')
            results[url] = self.analyze_url(url, message)

            # Group suggestions
            status = results[url]['status']
            self.suggestions[status].append(url)

        return results

    def generate_report(self) -> str:
        """Generate analysis report"""
        lines = []
        lines.append("=" * 80)
        lines.append("🔍 URL ANALYSIS REPORT")
        lines.append("=" * 80)
        lines.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        lines.append(f"Total invalid URLs: {len(self.invalid_urls)}")
        lines.append("")

        # Summary by status
        lines.append("📊 STATUS SUMMARY:")
        for status, urls in sorted(self.suggestions.items()):
            count = len(urls)
            status_icon = {
                'timeout': '⏰',
                'not_found': '🔍',
                'version_mismatch': '📦',
                'github_tag_mismatch': '🏷️',
                'apache_version_mismatch': '🌐',
                'gnome_version_mismatch': '🐧',
                'sourceforge_issue': '📂',
                'connection_refused': '🚫',
                'ssl_error': '🔒',
                'blocked': '🛡️',
                'needs_manual': '👤'
            }.get(status, '❓')

            pct = count / len(self.invalid_urls) * 100
            lines.append(f"  {status_icon} {status}: {count} ({pct:.1f}%)")
        lines.append("")

        # Detailed fixes
        lines.append("🔧 FIX SUGGESTIONS:")
        lines.append("")

        for url, analysis in self.analyze_all().items():
            status = analysis['status']
            icon = {
                'timeout': '⏰',
                'not_found': '🔍',
                'version_mismatch': '📦',
                'github_tag_mismatch': '🏷️',
                'apache_version_mismatch': '🌐',
                'gnome_version_mismatch': '🐧',
                'sourceforge_issue': '📂',
                'connection_refused': '🚫',
                'ssl_error': '🔒',
                'blocked': '🛡️'
            }.get(status, '❓')

            lines.append(f"{icon} {status.upper()}")
            lines.append(f"   URL: {url[:80]}...")
            lines.append(f"   Error: {analysis['error']}")

            if analysis['fix']:
                lines.append(f"   ✅ Fix: {analysis['fix']}")
            if analysis['note']:
                lines.append(f"   📝 Note: {analysis['note']}")
            lines.append("")

        lines.append("=" * 80)

        # Recommendations
        lines.append("💡 RECOMMENDATIONS:")
        lines.append("")

        if self.suggestions.get('timeout'):
            lines.append("1. GNU FTP Timeouts:")
            lines.append("   - Increase timeout: python3 validate_urls.py --timeout 60")
            lines.append("   - Use mirrors: https://mirrors.kernel.org/gnu/")
            lines.append("   - Try alternative versions (see VERSION_FIXES in the script)")
            lines.append("")

        if self.suggestions.get('github_tag_mismatch'):
            lines.append("2. GitHub Tag Issues:")
            lines.append("   - Check if the tag exists on GitHub")
            lines.append("   - Try using 'main' or 'master' branch instead of tags")
            lines.append("   - Format: https://github.com/user/repo/archive/refs/heads/main.tar.gz")
            lines.append("")

        if self.suggestions.get('apache_version_mismatch'):
            lines.append("3. Apache Version Issues:")
            lines.append("   - Check for newer versions at https://dlcdn.apache.org/")
            lines.append("   - Update version numbers in sources.list")
            lines.append("")

        if self.suggestions.get('not_found'):
            lines.append("4. 404 Errors:")
            lines.append("   - The file doesn't exist at this URL")
            lines.append("   - Check if the version number is correct")
            lines.append("   - Visit the project's website for current versions")
            lines.append("")

        if self.suggestions.get('ssl_error'):
            lines.append("5. SSL Errors:")
            lines.append("   - Try HTTP instead of HTTPS")
            lines.append("   - Update your SSL certificates")
            lines.append("")

        lines.append("=" * 80)

        return "\n".join(lines)

    def generate_fixed_sources(self) -> str:
        """Generate a fixed sources list with suggestions"""
        lines = []
        lines.append("# LFS Sources - Fixed URLs (with suggestions)")
        lines.append(f"# Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        lines.append("# NOTE: Some URLs have suggested fixes - verify before using")
        lines.append("")

        # Get all valid URLs from the report
        valid_urls = [r['url'] for r in self.data.get('results', []) if r.get('valid') is True]

        lines.append("# VALID URLs (from validation)")
        for url in valid_urls:
            lines.append(url)

        lines.append("")
        lines.append("# SUGGESTED FIXES FOR INVALID URLs")
        lines.append("# (Uncomment and verify before using)")

        for url, analysis in self.analyze_all().items():
            if analysis['fix']:
                lines.append(f"# {analysis['status'].upper()}: {analysis['error']}")
                lines.append(f"# Original: {url}")
                lines.append(f"# Suggested: {analysis['fix']}")
                if analysis['note']:
                    lines.append(f"# Note: {analysis['note']}")
                lines.append("")

        return "\n".join(lines)

    def save_fixes(self, output_dir: Path = Path('packages')):
        """Save fix suggestions to files"""
        output_dir.mkdir(exist_ok=True)

        # Save analysis report
        report_file = output_dir / 'url_analysis_report.txt'
        with open(report_file, 'w') as f:
            f.write(self.generate_report())
        print(f" Analysis report: {report_file}")

        # Save fixed sources
        fixed_file = output_dir / 'sources.list.fixed'
        with open(fixed_file, 'w') as f:
            f.write(self.generate_fixed_sources())
        print(f" Fixed sources: {fixed_file}")

        # Save suggested fixes by category
        categories_file = output_dir / 'suggested_fixes_by_category.txt'
        with open(categories_file, 'w') as f:
            f.write("# Suggested URL Fixes by Category\n\n")
            for status, urls in self.suggestions.items():
                f.write(f"\n## {status.upper()} ({len(urls)} URLs)\n\n")
                for url in urls:
                    analysis = self.analyze_url(url, '')
                    f.write(f"Original: {url}\n")
                    if analysis['fix']:
                        f.write(f"  → Fix: {analysis['fix']}\n")
                    if analysis['note']:
                        f.write(f"  → Note: {analysis['note']}\n")
                    f.write("\n")

        print(f" Categorized fixes: {categories_file}")

        # Create a shell script to download fixed URLs
        script_file = output_dir / 'download_fixed_sources.sh'
        with open(script_file, 'w') as f:
            f.write("#!/bin/bash\n")
            f.write("# Download fixed sources\n\n")
            f.write("mkdir -p sources\n\n")
            for url, analysis in self.analyze_all().items():
                if analysis['fix']:
                    f.write(f"# Original: {url}\n")
                    f.write(f"wget -c --timeout=60 --tries=3 -P sources/ {analysis['fix']}\n\n")

        script_file.chmod(0o755)
        print(f" Download script: {script_file}")

def main():
    """Main function"""
    print("=" * 80)
    print("🔍 LFS URL Analysis Tool")
    print("=" * 80)
    print()

    # Check if report exists
    report_file = Path('packages/sources_report.json')
    if not report_file.exists():
        print(" No validation report found!")
        print("Please run validation first:")
        print("  python3 validate_urls.py packages/sources.list")
        return

    # Analyze
    print(" Analyzing validation results...")
    analyzer = URLAnalyzer(report_file)

    # Generate reports
    print(f"Found {len(analyzer.invalid_urls)} invalid URLs")
    print()

    analyzer.save_fixes()
    print()

    # Show summary
    print(" Quick Summary:")
    print("-" * 40)
    for status, urls in analyzer.suggestions.items():
        print(f"  {status}: {len(urls)}")
    print()

    print(" Next Steps:")
    print("  1. Review: cat packages/url_analysis_report.txt")
    print("  2. Check fixes: cat packages/sources.list.fixed")
    print("  3. Download: ./packages/download_fixed_sources.sh")
    print("  4. Re-validate: python3 validate_urls.py --timeout 60")

if __name__ == "__main__":
    main()