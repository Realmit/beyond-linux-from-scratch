# After LFS installation, run:

# Initialize package database
lpm update

# Install a package from source
lpm install myapp https://example.com/myapp.tar.gz 1.0.0

# Install from binary package
lpm install /var/cache/lpm/packages/java-21.0.6.lpm

# List installed packages
lpm list

# Search for packages
lpm search "java"

# Remove a package
lpm remove openjdk

# Create your own package
lpm create my-custom-app 1.0.0
# Then follow prompts to select files

# Create PKGBUILD for a package
lpm-build create myapp
# Edit PKGBUILD file
lpm-build build .