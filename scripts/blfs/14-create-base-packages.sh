#!/bin/bash
# Create LPM packages for all installed components

set -e

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }

# Package definitions
declare -A PACKAGES=(
    ["java"]="/opt/jdk-21.0.6"
    ["maven"]="/opt/maven"
    ["gradle"]="/opt/gradle"
    ["tomcat"]="/opt/tomcat"
    ["nodejs"]="/opt/node"
    ["docker"]="/opt/docker"
    ["jenkins"]="/opt/jenkins"
)

# Create packages for each component
for pkg in "${!PACKAGES[@]}"; do
    log_info "Creating package: $pkg"

    # Create temporary package directory
    pkg_dir="/tmp/pkg-${pkg}"
    mkdir -p "$pkg_dir/metadata"

    # Create metadata
    echo "$pkg" > "$pkg_dir/metadata/name"
    echo "1.0.0" > "$pkg_dir/metadata/version"
    echo "lfs" > "$pkg_dir/metadata/packager"

    # Copy files
    cp -r "${PACKAGES[$pkg]}" "$pkg_dir/"

    # Create archive
    cd /tmp
    tar -czf "/var/cache/lpm/packages/${pkg}-1.0.0.lpm" "pkg-${pkg}"
    rm -rf "$pkg_dir"

    log_info "Package created: /var/cache/lpm/packages/${pkg}-1.0.0.lpm"
done

# Create package repository index
cat > /var/lib/lpm/repos/local.db << 'EOF'
# Local Package Repository
java:21.0.6:local:/var/cache/lpm/packages/java-1.0.0.lpm
maven:3.9.6:local:/var/cache/lpm/packages/maven-1.0.0.lpm
gradle:8.5:local:/var/cache/lpm/packages/gradle-1.0.0.lpm
tomcat:10.1.16:local:/var/cache/lpm/packages/tomcat-1.0.0.lpm
nodejs:20.11.0:local:/var/cache/lpm/packages/nodejs-1.0.0.lpm
docker:24.0.7:local:/var/cache/lpm/packages/docker-1.0.0.lpm
jenkins:2.440:local:/var/cache/lpm/packages/jenkins-1.0.0.lpm
EOF

log_success "Base packages created in /var/cache/lpm/packages/"