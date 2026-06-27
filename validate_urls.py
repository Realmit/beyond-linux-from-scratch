#!/usr/bin/env python3
"""
URL Validator for LFS Sources List
Checks that all URLs in sources.list are accessible
Usage: python3 validate_urls.py [sources.list]
"""

import sys
import re
import urllib.request
import urllib.error
import urllib.parse
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import time
from typing import List, Tuple, Optional
import json
from datetime import datetime

# Terminal colors
class Colors:
    GREEN = '\033[92m'
    RED = '\033[91m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    MAGENTA = '\033[95m'
    RESET = '\033[0m'
    BOLD = '\033[1m'

class URLValidator:
    """URL validator with support for Git patterns and HTTP"""

    # Patterns to ignore
    IGNORE_PATTERNS = [
        r'^#',  # Comments
        r'^$',  # Empty lines
        r'\.pdf$',  # PDF files (can be large)
        r'\.patch$',  # Patches (checked separately)
        r'git\.savannah\.gnu\.org',  # Git URLs
        r'git@',  # SSH Git URLs
        r'\.git$',  # Git URLs
    ]

    # Patterns for URLs that might be slow
    SLOW_URL_PATTERNS = [
        r'kernel\.org',
        r'gnu\.org',
        r'download\.gnome\.org',
        r'ftp\.mozilla\.org',
        r'download\.docker\.com',
    ]

    def __init__(self, timeout: int = 10, max_workers: int = 10, verbose: bool = False):
        self.timeout = timeout
        self.max_workers = max_workers
        self.verbose = verbose
        self.results = []
        self.stats = {
            'total': 0,
            'valid': 0,
            'invalid': 0,
            'ignored': 0,
            'git': 0,
            'slow': 0,
            'timeout': 0,
            'error': 0
        }

        # Configure urllib with good timeouts
        self.opener = urllib.request.build_opener()
        self.opener.addheaders = [
            ('User-Agent', 'Mozilla/5.0 (LFS URL Validator)'),
            ('Accept', '*/*'),
            ('Connection', 'close'),
        ]

    def _get_domain(self, url: str) -> str:
        """Extract domain from URL safely"""
        try:
            parsed = urllib.parse.urlparse(url)
            domain = parsed.netloc.lower()
            # Remove leading www.
            if domain.startswith('www.'):
                domain = domain[4:]
            return domain
        except Exception:
            return ''

    def should_ignore(self, url: str) -> Tuple[bool, str]:
        """Check if URL should be ignored"""
        url = url.strip()

        # Empty lines or comments
        if not url or url.startswith('#'):
            return True, "comment or empty"

        # Ignore patterns
        for pattern in self.IGNORE_PATTERNS:
            if re.search(pattern, url, re.IGNORECASE):
                return True, f"matches pattern: {pattern}"

        return False, ""

    def is_git_url(self, url: str) -> bool:
        """Check if this is a Git URL"""
        # Check scheme or obvious git indicators
        if (url.startswith('git://') or
                url.startswith('git@') or
                url.endswith('.git')):
            return True

        # Parse domain and check against known Git hosting services
        domain = self._get_domain(url)
        # Known Git hosting domains (excluding release archives)
        git_domains = {
            'git.savannah.gnu.org',
            'git.kernel.org',
            'github.com',
            'gitlab.com',
            'bitbucket.org'
        }
        if domain in git_domains:
            # For GitHub, if the path contains '/archive/' it's a release tarball, not a Git URL
            if domain == 'github.com':
                parsed = urllib.parse.urlparse(url)
                path = parsed.path.lower()
                if '/archive/' in path:
                    return False
            return True
        return False

    def is_slow_url(self, url: str) -> bool:
        """Check if URL is likely to be slow"""
        for pattern in self.SLOW_URL_PATTERNS:
            if re.search(pattern, url, re.IGNORECASE):
                return True
        return False

    def check_url(self, url: str) -> Tuple[str, bool, Optional[str]]:
        """Check a single URL"""
        url = url.strip()

        # Check if URL should be ignored
        should_ignore, reason = self.should_ignore(url)
        if should_ignore:
            return url, None, f"IGNORED ({reason})"

        # Git URLs - just check if server responds
        if self.is_git_url(url):
            try:
                # Extract domain
                parsed = urllib.parse.urlparse(url)
                domain = parsed.netloc
                # Ping the Git server (HEAD on /)
                git_check_url = f"{parsed.scheme}://{domain}/"
                req = urllib.request.Request(git_check_url, method='HEAD')
                response = self.opener.open(req, timeout=self.timeout)
                return url, True, f"GIT (server OK: {response.getcode()})"
            except Exception as e:
                return url, False, f"GIT (server error: {str(e)[:50]})"

        # HTTP/HTTPS URLs - check with HEAD then GET
        try:
            # First HEAD to save bandwidth
            req = urllib.request.Request(url, method='HEAD')
            response = self.opener.open(req, timeout=self.timeout)

            # If HEAD succeeds, consider URL valid
            status = response.getcode()
            if 200 <= status < 400:
                return url, True, f"OK (HEAD {status})"

            # If HEAD returns 405 (Method Not Allowed), try GET
            if status == 405:
                req = urllib.request.Request(url, method='GET')
                response = self.opener.open(req, timeout=self.timeout)
                status = response.getcode()
                if 200 <= status < 400:
                    # Read only a few bytes to minimize transfer
                    response.read(1024)
                    return url, True, f"OK (GET {status})"
                return url, False, f"GET {status}"

            return url, False, f"HEAD {status}"

        except urllib.error.HTTPError as e:
            # HTTP 404, 403, etc.
            if e.code == 404:
                return url, False, f"HTTP 404 NOT FOUND"
            elif e.code == 403:
                return url, True, f"HTTP 403 (access denied, but exists)"
            elif e.code == 429:
                return url, True, f"HTTP 429 (rate limited, likely exists)"
            else:
                return url, False, f"HTTP {e.code}: {e.reason}"

        except urllib.error.URLError as e:
            if "timed out" in str(e).lower():
                return url, False, f"TIMEOUT ({self.timeout}s)"
            elif "connection refused" in str(e).lower():
                return url, False, "CONNECTION REFUSED"
            elif "name resolution" in str(e).lower():
                return url, False, "DNS RESOLUTION FAILED"
            else:
                return url, False, f"URL ERROR: {str(e)[:50]}"

        except Exception as e:
            return url, False, f"ERROR: {str(e)[:50]}"

    def validate_file(self, filepath: Path) -> List[Tuple[str, bool, Optional[str]]]:
        """Validate all URLs in a file"""
        if not filepath.exists():
            print(f"{Colors.RED} File not found: {filepath}{Colors.RESET}")
            return []

        print(f"{Colors.CYAN} Reading file: {filepath}{Colors.RESET}")

        # Read all URLs
        urls = []
        with open(filepath, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#'):
                    # Extract URLs (may contain inline comments)
                    parts = line.split('#')
                    url = parts[0].strip()
                    if url:
                        urls.append(url)

        self.stats['total'] = len(urls)
        print(f"{Colors.CYAN} {len(urls)} URLs found{Colors.RESET}")

        # Filter URLs to ignore
        valid_urls = []
        ignored_count = 0
        for url in urls:
            should_ignore, reason = self.should_ignore(url)
            if should_ignore:
                ignored_count += 1
                self.results.append((url, None, f"IGNORED ({reason})"))
            else:
                valid_urls.append(url)

        self.stats['ignored'] = ignored_count

        if not valid_urls:
            print(f"{Colors.YELLOW}  No URLs to check{Colors.RESET}")
            return self.results

        print(f"{Colors.CYAN} Checking {len(valid_urls)} URLs (timeout: {self.timeout}s, workers: {self.max_workers}){Colors.RESET}")
        print("-" * 80)

        # Check in parallel
        with ThreadPoolExecutor(max_workers=self.max_workers) as executor:
            future_to_url = {executor.submit(self.check_url, url): url for url in valid_urls}

            for future in as_completed(future_to_url):
                url = future_to_url[future]
                try:
                    result_url, is_valid, message = future.result()
                    self.results.append((result_url, is_valid, message))

                    # Update stats
                    if is_valid is None:
                        self.stats['ignored'] += 1
                    elif is_valid:
                        self.stats['valid'] += 1
                        if self.is_git_url(url):
                            self.stats['git'] += 1
                        if self.is_slow_url(url):
                            self.stats['slow'] += 1
                    else:
                        self.stats['invalid'] += 1
                        if message and 'TIMEOUT' in message:
                            self.stats['timeout'] += 1
                        elif message and 'ERROR' in message:
                            self.stats['error'] += 1

                    # Display result
                    if is_valid is None:
                        status_color = Colors.YELLOW
                        status_icon = "⚠️"
                    elif is_valid:
                        status_color = Colors.GREEN
                        status_icon = "✅"
                    else:
                        status_color = Colors.RED
                        status_icon = "❌"

                    # Truncate URL for display
                    display_url = url[:70] + "..." if len(url) > 70 else url
                    print(f"{status_color} {status_icon} {display_url}")
                    if self.verbose and message:
                        print(f"   └─ {message}{Colors.RESET}")
                    elif not self.verbose and is_valid is not None and not is_valid:
                        print(f"   └─ {Colors.RED}{message}{Colors.RESET}")

                except Exception as e:
                    print(f"{Colors.RED} Error checking {url}: {e}{Colors.RESET}")
                    self.results.append((url, False, f"EXCEPTION: {str(e)[:50]}"))
                    self.stats['invalid'] += 1

        return self.results

    def generate_report(self) -> str:
        """Generate a detailed report"""
        report = []
        report.append("=" * 80)
        report.append(f"{Colors.BOLD}📊 URL VALIDATION REPORT{Colors.RESET}")
        report.append("=" * 80)
        report.append(f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        report.append("")

        # General statistics
        total = self.stats['total']
        valid = self.stats['valid']
        invalid = self.stats['invalid']
        ignored = self.stats['ignored']
        git = self.stats['git']
        timeout = self.stats['timeout']
        error = self.stats['error']

        report.append(f"{Colors.BOLD}📈 STATISTICS:{Colors.RESET}")
        report.append(f"  Total URLs:          {total}")
        report.append(f"  ✅ Valid:             {valid} ({valid/total*100:.1f}%)")
        report.append(f"  ❌ Invalid:           {invalid} ({invalid/total*100:.1f}%)")
        report.append(f"  ⚠️  Ignored:           {ignored} ({ignored/total*100:.1f}%)")
        report.append(f"  🔄 Git URLs:          {git}")
        report.append(f"  ⏰ Timeouts:          {timeout}")
        report.append(f"  ❌ Errors:            {error}")
        report.append("")

        # Invalid URLs
        invalid_urls = [(url, msg) for url, valid, msg in self.results if valid is False]
        if invalid_urls:
            report.append(f"{Colors.RED}❌ INVALID URLs:{Colors.RESET}")
            for url, msg in invalid_urls:
                report.append(f"  {url[:80]}...")
                report.append(f"    └─ {Colors.RED}{msg}{Colors.RESET}")
            report.append("")

        # Slow URLs
        slow_urls = [(url, msg) for url, valid, msg in self.results
                     if valid is True and self.is_slow_url(url)]
        if slow_urls:
            report.append(f"{Colors.YELLOW}🐌 SLOW URLs (potentially):{Colors.RESET}")
            for url, msg in slow_urls[:10]:  # Limit to 10
                report.append(f"  {url[:80]}...")
            if len(slow_urls) > 10:
                report.append(f"  ... and {len(slow_urls) - 10} more")
            report.append("")

        # Domain summary
        domains = {}
        for url, valid, msg in self.results:
            if valid is None:
                continue
            try:
                parsed = urllib.parse.urlparse(url)
                domain = parsed.netloc
                if domain:
                    if domain not in domains:
                        domains[domain] = {'valid': 0, 'invalid': 0, 'total': 0}
                    domains[domain]['total'] += 1
                    if valid:
                        domains[domain]['valid'] += 1
                    else:
                        domains[domain]['invalid'] += 1
            except:
                pass

        if domains:
            report.append(f"{Colors.BOLD}🌐 DOMAINS:{Colors.RESET}")
            sorted_domains = sorted(domains.items(), key=lambda x: x[1]['total'], reverse=True)
            for domain, stats in sorted_domains:
                status = "✅" if stats['invalid'] == 0 else "⚠️"
                report.append(f"  {status} {domain}: {stats['valid']} valid / {stats['invalid']} invalid")
            report.append("")

        report.append("=" * 80)

        return "\n".join(report)

    def save_report(self, output_file: Path):
        """Save report to a file"""
        report = self.generate_report()
        with open(output_file, 'w') as f:
            f.write(report)

        # Also save as JSON for automated processing
        json_data = {
            'stats': self.stats,
            'results': [{'url': url, 'valid': valid, 'message': msg}
                        for url, valid, msg in self.results],
            'timestamp': datetime.now().isoformat()
        }
        json_file = output_file.with_suffix('.json')
        with open(json_file, 'w') as f:
            json.dump(json_data, f, indent=2)

        print(f"\n{Colors.GREEN}📁 Report saved: {output_file}{Colors.RESET}")
        print(f"📁 JSON data: {json_file}")

def main():
    import argparse

    parser = argparse.ArgumentParser(description='Validate URLs in LFS sources list file')
    parser.add_argument('file', nargs='?', default='packages/sources.list',
                        help='sources.list file to validate')
    parser.add_argument('--timeout', type=int, default=10,
                        help='Timeout in seconds (default: 10)')
    parser.add_argument('--workers', type=int, default=10,
                        help='Number of parallel workers (default: 10)')
    parser.add_argument('--verbose', '-v', action='store_true',
                        help='Verbose mode')
    parser.add_argument('--output', '-o', help='Report output file')
    parser.add_argument('--quiet', '-q', action='store_true',
                        help='Quiet mode (no live output)')

    args = parser.parse_args()

    filepath = Path(args.file)
    if not filepath.exists():
        print(f"{Colors.RED} File not found: {filepath}{Colors.RESET}")
        sys.exit(1)

    # Initialize validator
    validator = URLValidator(
        timeout=args.timeout,
        max_workers=args.workers,
        verbose=args.verbose
    )

    # Validate
    validator.validate_file(filepath)

    # Display report
    if not args.quiet:
        print("\n" + validator.generate_report())

    # Save report
    if args.output:
        validator.save_report(Path(args.output))
    else:
        # Default report
        report_file = filepath.parent / f"{filepath.stem}_report.txt"
        validator.save_report(report_file)

    # Return code
    if validator.stats['invalid'] > 0:
        sys.exit(1)  # Some URLs are invalid
    else:
        sys.exit(0)  # All good

if __name__ == '__main__':
    main()