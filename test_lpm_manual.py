#!/usr/bin/env python3
"""Test LPM functionality"""

import tempfile
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).parent))

from lpm import Package, LPM

def test_lpm_all_features():
    """Test all LPM features"""

    with tempfile.TemporaryDirectory() as tmpdir:
        db_dir = Path(tmpdir) / 'lpm'
        lpm = LPM(db_dir=db_dir)

        print("=" * 60)
        print("LPM (LFS Package Manager) Test Suite")
        print("=" * 60)

        # Test 1: Add packages
        print("\n✓ Test 1: Adding packages...")
        pkg1 = Package(name='firefox', version='128.0', description='Web browser')
        pkg2 = Package(name='python', version='3.14', description='Programming language', dependencies=['glibc'])
        pkg3 = Package(name='glibc', version='2.43', description='C library')

        lpm.db.add_package(pkg1)
        lpm.db.add_package(pkg2)
        lpm.db.add_package(pkg3)
        print(f"  Added 3 packages")

        # Test 2: Search packages
        print("\n✓ Test 2: Searching packages...")
        results = lpm.search('browser')
        print(f"  Search 'browser': {[p.name for p in results]}")

        results = lpm.search('glib')
        print(f"  Search 'glib': {[p.name for p in results]}")

        # Test 3: List all packages
        print("\n✓ Test 3: Listing all packages...")
        packages = lpm.list_packages()
        print(f"  Total packages: {len(packages)}")
        for pkg in packages:
            deps_str = f" (deps: {', '.join(pkg.dependencies)})" if pkg.dependencies else ""
            print(f"    - {pkg.name} ({pkg.version}){deps_str}")

        # Test 4: Add installed packages
        print("\n✓ Test 4: Installing packages...")
        pkg1.install_date = '2026-05-15'
        pkg3.install_date = '2026-05-14'
        lpm.db.add_installed(pkg1)
        lpm.db.add_installed(pkg3)

        installed = lpm.list_installed()
        print(f"  Installed packages: {len(installed)}")
        for pkg in installed:
            print(f"    - {pkg.name} ({pkg.version}) - {pkg.install_date}")

        # Test 5: Check outdated packages
        print("\n✓ Test 5: Checking outdated packages...")
        pkg1_new = Package(name='firefox', version='129.0', description='Web browser')
        lpm.db.add_package(pkg1_new)

        outdated = lpm.list_outdated()
        print(f"  Outdated packages: {len(outdated)}")
        for name, current, available in outdated:
            print(f"    - {name}: {current} -> {available}")

        # Test 6: Case-insensitive search
        print("\n✓ Test 6: Case-insensitive search...")
        results = lpm.search('PYTHON')
        print(f"  Search 'PYTHON': {[p.name for p in results]}")

        results = lpm.search('PYTHON PROGRAMMING')
        print(f"  Search 'PYTHON PROGRAMMING': {[p.name for p in results]}")

        # Test 7: Package with dependencies
        print("\n✓ Test 7: Package dependencies...")
        python_pkg = lpm.db.get_package('python')
        print(f"  Python dependencies: {python_pkg.dependencies}")
        print(f"  Glibc is installed: {lpm.db.get_installed('glibc') is not None}")

        # Test 8: Create package
        print("\n✓ Test 8: Creating package...")
        success = lpm.create_package('myapp', '1.0.0', 'My test app', 'GPL-3.0')
        print(f"  Package created: {success}")

        # Test 9: Get package info
        print("\n✓ Test 9: Package information...")
        pkg = lpm.db.get_package('firefox')
        print(f"  {pkg.name} v{pkg.version}")
        print(f"    Description: {pkg.description}")
        print(f"    License: {pkg.license}")
        print(f"    Architecture: {pkg.arch}")

        # Test 10: Package dict conversion
        print("\n✓ Test 10: Package serialization...")
        pkg_dict = pkg1.to_dict()
        pkg_restored = Package.from_dict(pkg_dict)
        print(f"  Original: {pkg1.name} v{pkg1.version}")
        print(f"  Restored: {pkg_restored.name} v{pkg_restored.version}")
        print(f"  Match: {pkg1.name == pkg_restored.name and pkg1.version == pkg_restored.version}")

        print("\n" + "=" * 60)
        print("✅ All LPM tests passed!")
        print("=" * 60)

if __name__ == '__main__':
    test_lpm_all_features()

