#!/usr/bin/env python3
"""
LFS URL Validator - Interactive Menu Tool
A comprehensive tool for validating and managing LFS sources URLs
"""

import sys
import os
import json
import re
import urllib.request
import urllib.error
import urllib.parse
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import List, Tuple, Optional, Dict
from datetime import datetime
from collections import defaultdict, Counter
import subprocess
import shutil

# Terminal colors
class Colors:
    GREEN = '\033[92m'
    RED = '\033[91m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    CYAN = '\033[96m'
    MAGENTA = '\033[95m'
    WHITE = '\033[97m'
    RESET = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'
    DIM = '\033[2m'

def clear_screen():
    """Clear terminal screen"""
    os.system('clear' if os.name == 'posix' else 'cls')

def print_header(text: str):
    """Print a formatted header"""
    print(f"\n{Colors.CYAN}{'='*70}{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.WHITE}{text.center(70)}{Colors.RESET}")
    print(f"{Colors.CYAN}{'='*70}{Colors.RESET}\n")

def print_section(text: str):
    """Print a section header"""
    print(f"\n{Colors.YELLOW}▶ {text}{Colors.RESET}")

def print_success(text: str):
    """Print success message"""
    print(f"{Colors.GREEN} {text}{Colors.RESET}")

def print_error(text: str):
    """Print error message"""
    print(f"{Colors.RED} {text}{Colors.RESET}")

def print_warning(text: str):
    """Print warning message"""
    print(f"{Colors.YELLOW}  {text}{Colors.RESET}")

def print_info(text: str):
    """Print info message"""
    print(f"{Colors.CYAN}  {text}{Colors.RESET}")

def print_dim(text: str):
    """Print dim text"""
    print(f"{Colors.DIM}  {text}{Colors.RESET}")

def get_user_choice(prompt: str, options: List[str], default: int = 0) -> int:
    """Get user choice from a menu"""
    print()
    for i, option in enumerate(options, 1):
        prefix = "▶ " if i == default else "  "
        print(f"{prefix}{i}. {option}")
    print()

    while True:
        try:
            choice = input(f"{Colors.CYAN}{prompt} [{default}]: {Colors.RESET}")
            if not choice:
                return default - 1
            choice = int(choice)
            if 1 <= choice <= len(options):
                return choice - 1
            print_error(f"Please enter a number between 1 and {len(options)}")
        except ValueError:
            print_error("Please enter a valid number")

def get_user_input(prompt: str, default: str = "") -> str:
    """Get user input with default"""
    if default:
        prompt = f"{prompt} [{default}]"
    result = input(f"{Colors.CYAN}{prompt}: {Colors.RESET}")
    return result if result else default

class URLValidator:
    """URL validator with support for Git patterns and HTTP"""

    IGNORE_PATTERNS = [
        r'^#', r'^$', r'\.pdf$', r'\.patch$',
        r'git\.savannah\.gnu\.org', r'git@', r'\.git$',
    ]

    SLOW_URL_PATTERNS = [
        r'kernel\.org', r'gnu\.org', r'download\.gnome\.org',
        r'ftp\.mozilla\.org', r'download\.docker\.com',
    ]

    def __init__(self, timeout: int = 10, max_workers: int = 10, verbose: bool = False):
        self.timeout = timeout
        self.max_workers = max_workers
        self.verbose = verbose
        self.results = []
        self.stats = {
            'total': 0, 'valid': 0, 'invalid': 0, 'ignored': 0,
            'git': 0, 'slow': 0, 'timeout': 0, 'error': 0
        }
        self.opener = urllib.request.build_opener()
        self.opener.addheaders = [
            ('User-Agent', 'Mozilla/5.0 (LFS URL Validator)'),
            ('Accept', '*/*'), ('Connection', 'close'),
        ]

    def should_ignore(self, url: str) -> Tuple[bool, str]:
        url = url.strip()
        if not url or url.startswith('#'):
            return True, "comment or empty"
        for pattern in self.IGNORE_PATTERNS:
            if re.search(pattern, url, re.IGNORECASE):
                return True, f"matches pattern: {pattern}"
        return False, ""

    def is_git_url(self, url: str) -> bool:
        return (url.startswith('git://') or url.startswith('git@') or
                url.endswith('.git') or 'git.savannah.gnu.org' in url or
                'git.kernel.org' in url or
                ('github.com' in url and '/archive/' not in url))

    def is_slow_url(self, url: str) -> bool:
        return any(re.search(p, url, re.IGNORECASE) for p in self.SLOW_URL_PATTERNS)

    def check_url(self, url: str) -> Tuple[str, bool, Optional[str]]:
        url = url.strip()
        should_ignore, reason = self.should_ignore(url)
        if should_ignore:
            return url, None, f"IGNORED ({reason})"

        if self.is_git_url(url):
            try:
                parsed = urllib.parse.urlparse(url)
                domain = parsed.netloc
                git_check_url = f"{parsed.scheme}://{domain}/"
                req = urllib.request.Request(git_check_url, method='HEAD')
                response = self.opener.open(req, timeout=self.timeout)
                return url, True, f"GIT (server OK: {response.getcode()})"
            except Exception as e:
                return url, False, f"GIT (server error: {str(e)[:50]})"

        try:
            req = urllib.request.Request(url, method='HEAD')
            response = self.opener.open(req, timeout=self.timeout)
            status = response.getcode()
            if 200 <= status < 400:
                return url, True, f"OK (HEAD {status})"
            if status == 405:
                req = urllib.request.Request(url, method='GET')
                response = self.opener.open(req, timeout=self.timeout)
                status = response.getcode()
                if 200 <= status < 400:
                    response.read(1024)
                    return url, True, f"OK (GET {status})"
                return url, False, f"GET {status}"
            return url, False, f"HEAD {status}"
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return url, False, "HTTP 404 NOT FOUND"
            elif e.code == 403:
                return url, True, "HTTP 403 (access denied, but exists)"
            elif e.code == 429:
                return url, True, "HTTP 429 (rate limited, likely exists)"
            return url, False, f"HTTP {e.code}: {e.reason}"
        except urllib.error.URLError as e:
            if "timed out" in str(e).lower():
                return url, False, f"TIMEOUT ({self.timeout}s)"
            elif "connection refused" in str(e).lower():
                return url, False, "CONNECTION REFUSED"
            elif "name resolution" in str(e).lower():
                return url, False, "DNS RESOLUTION FAILED"
            return url, False, f"URL ERROR: {str(e)[:50]}"
        except Exception as e:
            return url, False, f"ERROR: {str(e)[:50]}"

    def validate_file(self, filepath: Path) -> List[Tuple[str, bool, Optional[str]]]:
        if not filepath.exists():
            print_error(f"File not found: {filepath}")
            return []

        print_info(f"Reading file: {filepath}")

        urls = []
        with open(filepath, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#'):
                    parts = line.split('#')
                    url = parts[0].strip()
                    if url:
                        urls.append(url)

        self.stats['total'] = len(urls)
        print_info(f"{len(urls)} URLs found")

        valid_urls = []
        for url in urls:
            should_ignore, reason = self.should_ignore(url)
            if should_ignore:
                self.stats['ignored'] += 1
                self.results.append((url, None, f"IGNORED ({reason})"))
            else:
                valid_urls.append(url)

        if not valid_urls:
            print_warning("No URLs to check")
            return self.results

        print_info(f"Checking {len(valid_urls)} URLs (timeout: {self.timeout}s, workers: {self.max_workers})")
        print("-" * 80)

        with ThreadPoolExecutor(max_workers=self.max_workers) as executor:
            future_to_url = {executor.submit(self.check_url, url): url for url in valid_urls}
            for future in as_completed(future_to_url):
                url = future_to_url[future]
                try:
                    result_url, is_valid, message = future.result()
                    self.results.append((result_url, is_valid, message))

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

                    icon = "✅" if is_valid else ("⚠️" if is_valid is None else "❌")
                    color = Colors.GREEN if is_valid else (Colors.YELLOW if is_valid is None else Colors.RED)
                    display_url = url[:70] + "..." if len(url) > 70 else url
                    print(f"{color}{icon} {display_url}{Colors.RESET}")
                    if self.verbose and message:
                        print(f"   └─ {message}")
                    elif not self.verbose and is_valid is not None and not is_valid:
                        print(f"   └─ {Colors.RED}{message}{Colors.RESET}")
                except Exception as e:
                    print_error(f"Error checking {url}: {e}")
                    self.results.append((url, False, f"EXCEPTION: {str(e)[:50]}"))
                    self.stats['invalid'] += 1

        return self.results

    def save_report(self, output_file: Path):
        """Save report to file"""
        report_file = Path(output_file)
        json_file = report_file.with_suffix('.json')

        # Save text report
        with open(report_file, 'w') as f:
            f.write(self.generate_report_text())

        # Save JSON
        json_data = {
            'stats': self.stats,
            'results': [{'url': url, 'valid': valid, 'message': msg}
                        for url, valid, msg in self.results],
            'timestamp': datetime.now().isoformat()
        }
        with open(json_file, 'w') as f:
            json.dump(json_data, f, indent=2)

        print_success(f"Report saved: {report_file}")
        print_success(f"JSON data: {json_file}")

    def generate_report_text(self) -> str:
        """Generate text report"""
        lines = []
        lines.append("=" * 80)
        lines.append("📊 URL VALIDATION REPORT")
        lines.append("=" * 80)
        lines.append(f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        lines.append("")

        total = self.stats['total']
        valid = self.stats['valid']
        invalid = self.stats['invalid']
        ignored = self.stats['ignored']

        lines.append("📈 STATISTICS:")
        lines.append(f"  Total URLs:          {total}")
        lines.append(f"  ✅ Valid:             {valid} ({valid/total*100:.1f}%)")
        lines.append(f"  ❌ Invalid:           {invalid} ({invalid/total*100:.1f}%)")
        lines.append(f"  ⚠️  Ignored:           {ignored} ({ignored/total*100:.1f}%)")
        lines.append(f"  ⏰ Timeouts:          {self.stats['timeout']}")
        lines.append(f"  🔄 Git URLs:          {self.stats['git']}")
        lines.append("")

        # Invalid URLs
        invalid_urls = [(url, msg) for url, valid, msg in self.results if valid is False]
        if invalid_urls:
            lines.append("❌ INVALID URLs:")
            for url, msg in invalid_urls:
                lines.append(f"  {url[:80]}...")
                lines.append(f"    └─ {msg}")
            lines.append("")

        lines.append("=" * 80)
        return "\n".join(lines)

class LFSSourcesManager:
    """Manage LFS sources and validation"""

    def __init__(self, sources_file: str = "packages/sources.list"):
        self.sources_file = Path(sources_file)
        self.report_file = self.sources_file.parent / f"{self.sources_file.stem}_report.txt"
        self.json_file = self.sources_file.parent / f"{self.sources_file.stem}_report.json"
        self.validator = None
        self.results = []
        self.stats = {}

    def validate(self, timeout: int = 10, workers: int = 10, verbose: bool = False):
        """Run validation"""
        print_header("URL VALIDATION")
        self.validator = URLValidator(timeout=timeout, max_workers=workers, verbose=verbose)
        self.results = self.validator.validate_file(self.sources_file)
        self.stats = self.validator.stats
        self.validator.save_report(self.report_file)
        return self.results

    def load_results(self):
        """Load results from JSON file"""
        if self.json_file.exists():
            with open(self.json_file) as f:
                data = json.load(f)
                self.stats = data.get('stats', {})
                self.results = [(r['url'], r['valid'], r.get('message', ''))
                                for r in data.get('results', [])]
            return True
        return False

    def get_valid_urls(self) -> List[str]:
        """Get list of valid URLs"""
        return [url for url, valid, _ in self.results if valid is True]

    def get_invalid_urls(self) -> List[Tuple[str, str]]:
        """Get list of invalid URLs with messages"""
        return [(url, msg) for url, valid, msg in self.results if valid is False]

    def get_urls_by_domain(self) -> Dict[str, List[str]]:
        """Group URLs by domain"""
        by_domain = defaultdict(list)
        for url, valid, _ in self.results:
            if valid is True:
                try:
                    domain = urllib.parse.urlparse(url).netloc
                    if domain:
                        by_domain[domain].append(url)
                except:
                    pass
        return dict(by_domain)

    def get_categorized_errors(self) -> Dict[str, List[str]]:
        """Categorize errors by type"""
        categories = defaultdict(list)
        for url, valid, msg in self.results:
            if valid is False:
                msg_lower = msg.lower()
                if '404' in msg_lower:
                    categories['404_NOT_FOUND'].append(url)
                elif 'timeout' in msg_lower:
                    categories['TIMEOUT'].append(url)
                elif 'refused' in msg_lower:
                    categories['CONNECTION_REFUSED'].append(url)
                elif 'dns' in msg_lower or 'resolution' in msg_lower:
                    categories['DNS_ERROR'].append(url)
                elif 'ssl' in msg_lower or 'certificate' in msg_lower:
                    categories['SSL_ERROR'].append(url)
                else:
                    categories['OTHER'].append(url)
        return dict(categories)

    def generate_validated_sources(self) -> Path:
        """Generate a sources list with only valid URLs"""
        output = self.sources_file.parent / "sources.list.validated"
        with open(output, 'w') as f:
            f.write("# LFS Sources - Validated URLs\n")
            f.write(f"# Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"# Valid URLs: {len(self.get_valid_urls())}\n\n")
            for url in self.get_valid_urls():
                f.write(f"{url}\n")
        return output

    def generate_domain_report(self) -> Path:
        """Generate report by domain"""
        output = self.sources_file.parent / "urls_by_domain.txt"
        by_domain = self.get_urls_by_domain()
        with open(output, 'w') as f:
            f.write("# URLs by Domain\n")
            f.write(f"# Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
            for domain, urls in sorted(by_domain.items()):
                f.write(f"\n# {domain} ({len(urls)} URLs)\n")
                for url in urls:
                    f.write(f"{url}\n")
        return output

def show_main_menu():
    """Display main menu"""
    clear_screen()
    print_header("LFS URL VALIDATOR - INTERACTIVE TOOL")

    print(f"{Colors.BOLD}Available Commands:{Colors.RESET}")
    print()
    options = [
        "Validate URLs (with default settings)",
        "Validate URLs (custom settings)",
        "Show validation report",
        "Show statistics",
        "Generate validated sources list",
        "Show invalid URLs",
        "Show URLs by domain",
        "Categorize errors",
        "Compare with original",
        "Export results",
        "Re-validate with longer timeout",
        "Help",
        "Exit"
    ]

    return get_user_choice("Select option", options, 1)

def validate_urls_interactive():
    """Interactive URL validation"""
    manager = LFSSourcesManager()

    if not manager.sources_file.exists():
        print_error(f"Sources file not found: {manager.sources_file}")
        print_info("Please create packages/sources.list first")
        return

    timeout = int(get_user_input("Timeout in seconds", "10"))
    workers = int(get_user_input("Number of parallel workers", "10"))
    verbose = get_user_input("Verbose output? (y/n)", "n").lower() == 'y'

    print()
    manager.validate(timeout=timeout, workers=workers, verbose=verbose)

    print_section("Validation Complete")
    print_success(f"Total: {manager.stats['total']}")
    print_success(f"Valid: {manager.stats['valid']}")
    print_error(f"Invalid: {manager.stats['invalid']}")
    print_warning(f"Ignored: {manager.stats['ignored']}")

    input(f"\n{Colors.DIM}Press Enter to continue...{Colors.RESET}")

def show_report():
    """Show the validation report"""
    manager = LFSSourcesManager()

    if not manager.load_results():
        print_error("No validation results found. Please run validation first.")
        return

    if manager.report_file.exists():
        print_header("VALIDATION REPORT")
        with open(manager.report_file) as f:
            print(f.read())
    else:
        print_error("Report file not found")

    input(f"\n{Colors.DIM}Press Enter to continue...{Colors.RESET}")

def show_statistics():
    """Show statistics"""
    manager = LFSSourcesManager()

    if not manager.load_results():
        print_error("No validation results found. Please run validation first.")
        return

    print_header("STATISTICS")

    stats = manager.stats
    total = stats.get('total', 0)
    valid = stats.get('valid', 0)
    invalid = stats.get('invalid', 0)
    ignored = stats.get('ignored', 0)

    print(f"Total URLs:          {total}")
    print(f"{Colors.GREEN} Valid:             {valid} ({valid/total*100:.1f}%){Colors.RESET}")
    print(f"{Colors.RED} Invalid:           {invalid} ({invalid/total*100:.1f}%){Colors.RESET}")
    print(f"{Colors.YELLOW} Ignored:           {ignored} ({ignored/total*100:.1f}%){Colors.RESET}")
    print(f" Timeouts:          {stats.get('timeout', 0)}")
    print(f" Git URLs:          {stats.get('git', 0)}")
    print(f" Slow URLs:         {stats.get('slow', 0)}")
    print(f" Errors:            {stats.get('error', 0)}")

    # Show error distribution
    categories = manager.get_categorized_errors()
    if categories:
        print(f"\n{Colors.BOLD}Error Distribution:{Colors.RESET}")
        for cat, urls in categories.items():
            print(f"  {cat}: {len(urls)} URLs")

    input(f"\n{Colors.DIM}Press Enter to continue...{Colors.RESET}")

def generate_validated_list():
    """Generate validated sources list"""
    manager = LFSSourcesManager()

    if not manager.load_results():
        print_error("No validation results found. Please run validation first.")
        return

    output = manager.generate_validated_sources()
    print_section("Validated Sources List Generated")
    print_success(f"File: {output}")
    print_success(f"Total valid URLs: {len(manager.get_valid_urls())}")

    choice = get_user_choice("Replace original sources.list?", ["No", "Yes"], 1)
    if choice == 1:
        print_info("Keeping original file")
    else:
        backup = manager.sources_file.with_suffix('.list.backup')
        shutil.copy2(manager.sources_file, backup)
        print_success(f"Backup created: {backup}")
        shutil.copy2(output, manager.sources_file)
        print_success(f"Replaced: {manager.sources_file}")

    input(f"\n{Colors.DIM}Press Enter to continue...{Colors.RESET}")

def show_invalid_urls():
    """Show invalid URLs"""
    manager = LFSSourcesManager()

    if not manager.load_results():
        print_error("No validation results found. Please run validation first.")
        return

    invalid = manager.get_invalid_urls()

    print_header(f"INVALID URLs ({len(invalid)})")

    if invalid:
        for url, msg in invalid:
            print(f"{Colors.RED} {url}{Colors.RESET}")
            print(f"   └─ {Colors.DIM}{msg}{Colors.RESET}")
            print()
    else:
        print_success("No invalid URLs found!")

    # Save to file
    if invalid:
        output = manager.sources_file.parent / "invalid_urls.txt"
        with open(output, 'w') as f:
            for url, msg in invalid:
                f.write(f"{url}\n")
        print_success(f"Invalid URLs saved to: {output}")

    input(f"\n{Colors.DIM}Press Enter to continue...{Colors.RESET}")

def show_domains():
    """Show URLs grouped by domain"""
    manager = LFSSourcesManager()

    if not manager.load_results():
        print_error("No validation results found. Please run validation first.")
        return

    by_domain = manager.get_urls_by_domain()

    print_header(f"URLs BY DOMAIN ({len(by_domain)} domains)")

    for domain, urls in sorted(by_domain.items()):
        print(f"\n{Colors.BOLD}{domain}{Colors.RESET} ({len(urls)} URLs)")
        for url in urls[:5]:  # Show first 5
            print(f"  {url}")
        if len(urls) > 5:
            print(f"  ... and {len(urls) - 5} more")

    # Generate domain report
    output = manager.generate_domain_report()
    print_success(f"Domain report saved: {output}")

    input(f"\n{Colors.DIM}Press Enter to continue...{Colors.RESET}")

def categorize_errors():
    """Show categorized errors"""
    manager = LFSSourcesManager()

    if not manager.load_results():
        print_error("No validation results found. Please run validation first.")
        return

    categories = manager.get_categorized_errors()

    print_header("ERRORS BY CATEGORY")

    if not categories:
        print_success("No errors found!")
        input(f"\n{Colors.DIM}Press Enter to continue...{Colors.RESET}")
        return

    for category, urls in sorted(categories.items()):
        print(f"\n{Colors.BOLD}{category}{Colors.RESET} ({len(urls)} URLs)")
        for url in urls[:10]:
            print(f"  {url}")
        if len(urls) > 10:
            print(f"  ... and {len(urls) - 10} more")

    # Save categorized errors
    output = manager.sources_file.parent / "categorized_invalid_urls.txt"
    with open(output, 'w') as f:
        for category, urls in categories.items():
            f.write(f"\n# {category} ({len(urls)} URLs)\n")
            for url in urls:
                f.write(f"{url}\n")
    print_success(f"Categorized errors saved: {output}")

    input(f"\n{Colors.DIM}Press Enter to continue...{Colors.RESET}")

def compare_with_original():
    """Compare validated list with original"""
    manager = LFSSourcesManager()

    if not manager.load_results():
        print_error("No validation results found. Please run validation first.")
        return

    print_header("COMPARISON WITH ORIGINAL")

    valid_urls = set(manager.get_valid_urls())
    invalid_urls = set(url for url, _ in manager.get_invalid_urls())

    # Read original URLs
    original_urls = set()
    if manager.sources_file.exists():
        with open(manager.sources_file) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#'):
                    parts = line.split('#')
                    url = parts[0].strip()
                    if url:
                        original_urls.add(url)

    total = len(original_urls)
    valid_count = len(valid_urls)
    invalid_count = len(invalid_urls)

    print(f"Total URLs in original:  {total}")
    print(f"{Colors.GREEN} Valid URLs:            {valid_count} ({valid_count/total*100:.1f}%){Colors.RESET}")
    print(f"{Colors.RED} Invalid URLs:          {invalid_count} ({invalid_count/total*100:.1f}%){Colors.RESET}")

    input(f"\n{Colors.DIM}Press Enter to continue...{Colors.RESET}")

def export_results():
    """Export results in various formats"""
    manager = LFSSourcesManager()

    if not manager.load_results():
        print_error("No validation results found. Please run validation first.")
        return

    print_header("EXPORT RESULTS")

    options = [
        "Export as CSV",
        "Export as Markdown",
        "Export as HTML",
        "Export as JSON (already available)",
        "Export all",
        "Back"
    ]

    while True:
        choice = get_user_choice("Select export format", options, 1)

        if choice == 0:
            export_csv(manager)
        elif choice == 1:
            export_markdown(manager)
        elif choice == 2:
            export_html(manager)
        elif choice == 3:
            print_info("JSON file already available: packages/sources_report.json")
        elif choice == 4:
            export_csv(manager)
            export_markdown(manager)
            export_html(manager)
            print_success("All exports completed")
        elif choice == 5:
            break

def export_csv(manager):
    """Export results as CSV"""
    output = manager.sources_file.parent / "url_report.csv"
    with open(output, 'w') as f:
        f.write("URL,Valid,Message\n")
        for url, valid, msg in manager.results:
            status = "Valid" if valid is True else ("Ignored" if valid is None else "Invalid")
            f.write(f'"{url}",{status},"{msg or ""}"\n')
    print_success(f"CSV exported: {output}")

def export_markdown(manager):
    """Export results as Markdown"""
    output = manager.sources_file.parent / "url_report.md"
    with open(output, 'w') as f:
        f.write("# LFS URL Validation Report\n\n")
        f.write(f"**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
        f.write("## Statistics\n\n")
        stats = manager.stats
        total = stats.get('total', 0)
        f.write("| Metric | Value |\n")
        f.write("|--------|-------|\n")
        f.write(f"| Total URLs | {total} |\n")
        f.write(f"|  Valid | {stats.get('valid', 0)} ({stats.get('valid', 0)/total*100:.1f}%) |\n")
        f.write(f"|  Invalid | {stats.get('invalid', 0)} ({stats.get('invalid', 0)/total*100:.1f}%) |\n")
        f.write(f"|  Ignored | {stats.get('ignored', 0)} |\n\n")

        invalid = manager.get_invalid_urls()
        if invalid:
            f.write("## Invalid URLs\n\n")
            for url, msg in invalid:
                f.write(f"- `{url}` - {msg}\n")

    print_success(f"Markdown exported: {output}")

def export_html(manager):
    """Export results as HTML"""
    output = manager.sources_file.parent / "url_report.html"
    with open(output, 'w') as f:
        f.write("""<!DOCTYPE html>
<html>
<head>
    <title>LFS URL Validation Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; }
        .stats { background: #f5f5f5; padding: 15px; border-radius: 5px; }
        .valid { color: green; }
        .invalid { color: red; }
        .ignored { color: orange; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background: #f0f0f0; }
        tr:hover { background: #f9f9f9; }
    </style>
</head>
<body>
""")
        f.write(f"<h1>LFS URL Validation Report</h1>\n")
        f.write(f"<p><strong>Generated:</strong> {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>\n")

        stats = manager.stats
        total = stats.get('total', 0)
        f.write("<div class='stats'>\n")
        f.write("<h2>Statistics</h2>\n")
        f.write("<ul>\n")
        f.write(f"<li>Total URLs: {total}</li>\n")
        f.write(f"<li class='valid'>  Valid: {stats.get('valid', 0)} ({stats.get('valid', 0)/total*100:.1f}%)</li>\n")
        f.write(f"<li class='invalid'>  Invalid: {stats.get('invalid', 0)} ({stats.get('invalid', 0)/total*100:.1f}%)</li>\n")
        f.write(f"<li class='ignored'>  Ignored: {stats.get('ignored', 0)}</li>\n")
        f.write("</ul>\n</div>\n")

        f.write("<h2>Results</h2>\n<table>\n<tr><th>URL</th><th>Status</th><th>Message</th></tr>\n")
        for url, valid, msg in manager.results:
            status = " Valid" if valid is True else (" Ignored" if valid is None else " Invalid")
            cls = "valid" if valid is True else ("ignored" if valid is None else "invalid")
            f.write(f'<tr class="{cls}"><td>{url}</td><td>{status}</td><td>{msg or ""}</td></tr>\n')
        f.write("</table>\n</body>\n</html>")

    print_success(f"HTML exported: {output}")

def revalidate_with_timeout():
    """Re-validate with longer timeout"""
    timeout = int(get_user_input("New timeout in seconds", "60"))
    workers = int(get_user_input("Number of parallel workers", "10"))
    verbose = get_user_input("Verbose output? (y/n)", "n").lower() == 'y'

    manager = LFSSourcesManager()
    manager.validate(timeout=timeout, workers=workers, verbose=verbose)
    print_success("Re-validation complete")

def show_help():
    """Show help"""
    print_header("HELP")
    print(f"""
{Colors.BOLD}LFS URL Validator - Interactive Tool{Colors.RESET}

This tool helps you validate and manage URLs in your LFS sources.list file.

{Colors.BOLD}Features:{Colors.RESET}
  • Validate all URLs in sources.list
  • Check HTTP/HTTPS and Git URLs
  • Generate reports (text, JSON, CSV, Markdown, HTML)
  • Filter valid/invalid URLs
  • Group URLs by domain
  • Categorize errors by type
  • Generate validated sources list

{Colors.BOLD}Usage:{Colors.RESET}
  1. Run validation first to check all URLs
  2. Review the report and statistics
  3. Generate validated sources list with working URLs
  4. Export results in your preferred format

{Colors.BOLD}Tips:{Colors.RESET}
  • Use longer timeout for GNU FTP URLs
  • Some URLs may require manual version checking
  • The validated list can replace your original sources.list

{Colors.BOLD}Files:{Colors.RESET}
  • packages/sources.list - Original sources file
  • packages/sources_report.txt - Text report
  • packages/sources_report.json - JSON data
  • packages/sources.list.validated - Working URLs only
  • packages/url_report.csv - CSV export
  • packages/url_report.md - Markdown export
  • packages/url_report.html - HTML export
    """)

    input(f"\n{Colors.DIM}Press Enter to continue...{Colors.RESET}")

def main():
    """Main program loop"""
    while True:
        choice = show_main_menu()

        if choice == 0:
            validate_urls_interactive()
        elif choice == 1:
            validate_urls_interactive()
        elif choice == 2:
            show_report()
        elif choice == 3:
            show_statistics()
        elif choice == 4:
            generate_validated_list()
        elif choice == 5:
            show_invalid_urls()
        elif choice == 6:
            show_domains()
        elif choice == 7:
            categorize_errors()
        elif choice == 8:
            compare_with_original()
        elif choice == 9:
            export_results()
        elif choice == 10:
            revalidate_with_timeout()
        elif choice == 11:
            show_help()
        elif choice == 12:
            print_header("Goodbye!")
            print("Thank you for using LFS URL Validator!")
            print()
            sys.exit(0)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\nExiting...")
        sys.exit(0)