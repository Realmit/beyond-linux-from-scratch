#!/bin/bash
# Create LPM packages for all installed components
# Version: 2.0 - Updated with dynamic version detection

set -e

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[0;34m[SUCCESS]\033[0m $1"; }
log_warning() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

# ============================================================================
# CONFIGURATION
# ============================================================================
LPM_CACHE="/var/cache/lpm/packages"
LPM_REPO_DB="/var/lib/lpm/repos/local.db"
PACKAGE_METADATA_DIR="/var/lib/lpm/package-metadata"

# Create directories
mkdir -p "$LPM_CACHE" "$PACKAGE_METADATA_DIR"

# ============================================================================
# VERSION DETECTION FUNCTIONS
# ============================================================================

detect_java_version() {
    if [ -f "/opt/jdk-21.0.8/bin/java" ]; then
        echo "21.0.8"
    elif [ -f "/opt/jdk-21.0.6/bin/java" ]; then
        echo "21.0.6"
    elif [ -f "/opt/jdk-17/bin/java" ]; then
        echo "17.0.0"
    else
        echo "unknown"
    fi
}

detect_maven_version() {
    if [ -f "/opt/maven/bin/mvn" ]; then
        /opt/maven/bin/mvn -version 2>/dev/null | head -1 | awk '{print $3}' || echo "3.9.9"
    else
        echo "unknown"
    fi
}

detect_gradle_version() {
    if [ -f "/opt/gradle/bin/gradle" ]; then
        /opt/gradle/bin/gradle -version 2>/dev/null | grep "Gradle" | awk '{print $2}' || echo "8.13"
    else
        echo "unknown"
    fi
}

detect_tomcat_version() {
    if [ -d "/opt/tomcat" ] && [ -f "/opt/tomcat/bin/version.sh" ]; then
        /opt/tomcat/bin/version.sh 2>/dev/null | grep "Server number" | awk '{print $3}' || echo "10.1.39"
    else
        echo "unknown"
    fi
}

detect_nodejs_version() {
    if [ -f "/opt/node/bin/node" ]; then
        /opt/node/bin/node --version 2>/dev/null | sed 's/v//' || echo "22.14.0"
    else
        echo "unknown"
    fi
}

detect_docker_version() {
    if [ -f "/usr/local/bin/docker" ]; then
        /usr/local/bin/docker --version 2>/dev/null | awk '{print $3}' | sed 's/,//' || echo "27.4.1"
    else
        echo "unknown"
    fi
}

detect_kubectl_version() {
    if [ -f "/usr/local/bin/kubectl" ]; then
        /usr/local/bin/kubectl version --client -o json 2>/dev/null | grep -o '"gitVersion":"[^"]*"' | cut -d'"' -f4 || echo "1.32.3"
    else
        echo "unknown"
    fi
}

detect_jenkins_version() {
    if [ -f "/opt/jenkins/jenkins.war" ]; then
        unzip -p /opt/jenkins/jenkins.war META-INF/MANIFEST.MF 2>/dev/null | grep "Implementation-Version" | cut -d' ' -f2 || echo "2.492.2"
    else
        echo "unknown"
    fi
}

detect_jmeter_version() {
    if [ -d "/opt/jmeter" ]; then
        echo "5.6.3"
    else
        echo "unknown"
    fi
}

detect_allure_version() {
    if [ -d "/opt/allure" ]; then
        echo "2.32.0"
    else
        echo "unknown"
    fi
}

# ============================================================================
# PACKAGE CREATION FUNCTION
# ============================================================================

create_package() {
    local pkg_name=$1
    local pkg_path=$2
    local pkg_version=$3
    local pkg_description=$4
    local pkg_dependencies=$5

    if [ ! -d "$pkg_path" ] && [ ! -f "$pkg_path" ]; then
        log_warning "Package path not found: $pkg_path (skipping $pkg_name)"
        return 1
    fi

    log_info "Creating package: $pkg_name-$pkg_version"

    # Create temporary package directory
    local pkg_dir="/tmp/pkg-${pkg_name}"
    rm -rf "$pkg_dir"
    mkdir -p "$pkg_dir/metadata"
    mkdir -p "$pkg_dir/usr/local"

    # Create metadata files
    echo "$pkg_name" > "$pkg_dir/metadata/name"
    echo "$pkg_version" > "$pkg_dir/metadata/version"
    echo "LFS Builder" > "$pkg_dir/metadata/packager"
    echo "$pkg_description" > "$pkg_dir/metadata/description"
    echo "$pkg_dependencies" > "$pkg_dir/metadata/dependencies"
    echo "$(date +%Y%m%d-%H%M%S)" > "$pkg_dir/metadata/build_date"

    # Calculate size
    local size=$(du -sb "$pkg_path" 2>/dev/null | cut -f1)
    echo "$size" > "$pkg_dir/metadata/installed_size"

    # Copy files
    cp -r "$pkg_path" "$pkg_dir/" 2>/dev/null || true

    # Create post-install script if needed
    if [ -f "packages/custom-scripts/${pkg_name}-post-install.sh" ]; then
        cp "packages/custom-scripts/${pkg_name}-post-install.sh" "$pkg_dir/metadata/post-install.sh"
        chmod +x "$pkg_dir/metadata/post-install.sh"
    fi

    # Create archive
    cd /tmp
    local pkg_file="${LPM_CACHE}/${pkg_name}-${pkg_version}.lpm"
    tar -czf "$pkg_file" "pkg-${pkg_name}" 2>/dev/null
    rm -rf "$pkg_dir"

    # Generate checksum
    local sha256=$(sha256sum "$pkg_file" | cut -d' ' -f1)
    echo "$sha256" > "${pkg_file}.sha256"

    log_success "Package created: $pkg_file"
    echo "  Size: $(du -h "$pkg_file" | cut -f1)"
    echo "  SHA256: ${sha256:0:32}..."

    return 0
}

# ============================================================================
# CREATE PACKAGE METADATA
# ============================================================================

create_package_metadata() {
    local pkg_name=$1
    local pkg_version=$2
    local pkg_size=$3

    cat >> "$LPM_REPO_DB" << EOF
${pkg_name}:${pkg_version}:local:${LPM_CACHE}/${pkg_name}-${pkg_version}.lpm:${pkg_size}
EOF
}

# ============================================================================
# MAIN PACKAGE CREATION
# ============================================================================

# Clear existing repository database
> "$LPM_REPO_DB"

# ============================================================================
# JAVA PACKAGE
# ============================================================================
JAVA_VERSION=$(detect_java_version)
if [ "$JAVA_VERSION" != "unknown" ]; then
    JAVA_PATH=$(ls -d /opt/jdk-* 2>/dev/null | head -1)
    if [ -n "$JAVA_PATH" ]; then
        create_package "java" "$JAVA_PATH" "$JAVA_VERSION" "OpenJDK Java Development Kit" "glibc"
        create_package_metadata "java" "$JAVA_VERSION" "500M"
    fi
fi

# ============================================================================
# MAVEN PACKAGE
# ============================================================================
MAVEN_VERSION=$(detect_maven_version)
if [ -d "/opt/maven" ]; then
    create_package "maven" "/opt/maven" "$MAVEN_VERSION" "Apache Maven build automation tool" "java"
    create_package_metadata "maven" "$MAVEN_VERSION" "50M"
fi

# ============================================================================
# GRADLE PACKAGE
# ============================================================================
GRADLE_VERSION=$(detect_gradle_version)
if [ -d "/opt/gradle" ]; then
    create_package "gradle" "/opt/gradle" "$GRADLE_VERSION" "Gradle build tool" "java"
    create_package_metadata "gradle" "$GRADLE_VERSION" "150M"
fi

# ============================================================================
# TOMCAT PACKAGE
# ============================================================================
TOMCAT_VERSION=$(detect_tomcat_version)
if [ -d "/opt/tomcat" ]; then
    create_package "tomcat" "/opt/tomcat" "$TOMCAT_VERSION" "Apache Tomcat servlet container" "java"
    create_package_metadata "tomcat" "$TOMCAT_VERSION" "120M"
fi

# ============================================================================
# NODE.JS PACKAGE
# ============================================================================
NODE_VERSION=$(detect_nodejs_version)
if [ -d "/opt/node" ]; then
    create_package "nodejs" "/opt/node" "$NODE_VERSION" "Node.js JavaScript runtime" ""
    create_package_metadata "nodejs" "$NODE_VERSION" "200M"
fi

# ============================================================================
# DOCKER PACKAGE
# ============================================================================
DOCKER_VERSION=$(detect_docker_version)
if command -v docker &> /dev/null; then
    create_package "docker" "/opt/docker" "$DOCKER_VERSION" "Docker container runtime" "containerd"
    create_package_metadata "docker" "$DOCKER_VERSION" "100M"
fi

# ============================================================================
# KUBECTL PACKAGE
# ============================================================================
KUBECTL_VERSION=$(detect_kubectl_version)
if command -v kubectl &> /dev/null; then
    mkdir -p /tmp/pkg-kubectl/usr/local/bin
    cp /usr/local/bin/kubectl /tmp/pkg-kubectl/usr/local/bin/
    create_package "kubectl" "/tmp/pkg-kubectl" "$KUBECTL_VERSION" "Kubernetes command-line tool" ""
    rm -rf /tmp/pkg-kubectl
    create_package_metadata "kubectl" "$KUBECTL_VERSION" "50M"
fi

# ============================================================================
# JENKINS PACKAGE
# ============================================================================
JENKINS_VERSION=$(detect_jenkins_version)
if [ -f "/opt/jenkins/jenkins.war" ]; then
    mkdir -p /tmp/pkg-jenkins/opt/jenkins
    cp /opt/jenkins/jenkins.war /tmp/pkg-jenkins/opt/jenkins/
    create_package "jenkins" "/tmp/pkg-jenkins" "$JENKINS_VERSION" "Jenkins CI/CD server" "java"
    rm -rf /tmp/pkg-jenkins
    create_package_metadata "jenkins" "$JENKINS_VERSION" "100M"
fi

# ============================================================================
# JMETER PACKAGE
# ============================================================================
JMETER_VERSION=$(detect_jmeter_version)
if [ -d "/opt/jmeter" ]; then
    create_package "jmeter" "/opt/jmeter" "$JMETER_VERSION" "Apache JMeter performance testing" "java"
    create_package_metadata "jmeter" "$JMETER_VERSION" "200M"
fi

# ============================================================================
# ALLURE PACKAGE
# ============================================================================
ALLURE_VERSION=$(detect_allure_version)
if [ -d "/opt/allure" ]; then
    create_package "allure" "/opt/allure" "$ALLURE_VERSION" "Allure test reporting framework" "java"
    create_package_metadata "allure" "$ALLURE_VERSION" "150M"
fi

# ============================================================================
# LFS CORE PACKAGES (Optional - can be created on demand)
# ============================================================================

create_lfs_core_packages() {
    log_info "Creating LFS core packages..."

    # Create package for systemd (if present)
    if command -v systemctl &> /dev/null; then
        SYSTEMD_VERSION=$(systemctl --version | head -1 | awk '{print $2}')
        mkdir -p /tmp/pkg-systemd/usr/lib/systemd
        cp -r /usr/lib/systemd/* /tmp/pkg-systemd/usr/lib/systemd/ 2>/dev/null || true
        create_package "systemd" "/tmp/pkg-systemd" "$SYSTEMD_VERSION" "Systemd init system" ""
        rm -rf /tmp/pkg-systemd
    fi

    # Create package for kernel
    KERNEL_VERSION=$(uname -r)
    mkdir -p /tmp/pkg-kernel/boot
    cp /boot/vmlinuz-* /tmp/pkg-kernel/boot/ 2>/dev/null || true
    create_package "kernel" "/tmp/pkg-kernel" "$KERNEL_VERSION" "Linux kernel" ""
    rm -rf /tmp/pkg-kernel
}

# ============================================================================
# CREATE REPOSITORY INDEX
# ============================================================================

create_repo_index() {
    log_info "Creating repository index..."

    # Add header
    cat > "$LPM_REPO_DB" << 'EOF'
# LFS Local Package Repository
# Format: name:version:repo:path:size
# Generated: $(date)
EOF

    # Add timestamp
    echo "# Generated: $(date +%Y%m%d-%H%M%S)" >> "$LPM_REPO_DB"

    # Scan for existing packages
    for pkg_file in "$LPM_CACHE"/*.lpm; do
        if [ -f "$pkg_file" ]; then
            local filename=$(basename "$pkg_file" .lpm)
            local name=$(echo "$filename" | cut -d- -f1)
            local version=$(echo "$filename" | cut -d- -f2-)
            local size=$(du -h "$pkg_file" | cut -f1)
            echo "${name}:${version}:local:${pkg_file}:${size}" >> "$LPM_REPO_DB"
        fi
    done

    # Sign the repository (if GPG key exists)
    if [ -f "/etc/lpm/private.key" ]; then
        gpg --detach-sign --armor "$LPM_REPO_DB"
        log_info "Repository signed with GPG"
    fi
}

# ============================================================================
# CREATE PACKAGE LIST FILE
# ============================================================================

create_package_list() {
    log_info "Creating package list..."

    cat > "/var/lib/lpm/available-packages.txt" << 'EOF'
========================================
LFS Available Package List
========================================

Core Packages:
  - java: Java Development Kit (JDK)
  - maven: Apache Maven build tool
  - gradle: Gradle build automation
  - nodejs: Node.js JavaScript runtime
  - docker: Container runtime
  - kubectl: Kubernetes CLI
  - jenkins: CI/CD server
  - jmeter: Performance testing
  - allure: Test reporting

Development Tools:
  - git: Version control
  - vim: Text editor
  - gcc: GNU C compiler
  - make: Build automation

Desktop Applications:
  - firefox: Web browser
  - libreoffice: Office suite
  - gimp: Image editor
  - vlc: Media player

To install a package:
  lpm install <package-name>

To search packages:
  lpm search <keyword>

EOF

    log_success "Package list created"
}

# ============================================================================
# PACKAGE VERIFICATION
# ============================================================================

verify_packages() {
    log_info "Verifying created packages..."

    local package_count=0
    local total_size=0

    for pkg_file in "$LPM_CACHE"/*.lpm; do
        if [ -f "$pkg_file" ]; then
            package_count=$((package_count + 1))
            size=$(stat -c%s "$pkg_file" 2>/dev/null || stat -f%z "$pkg_file" 2>/dev/null)
            total_size=$((total_size + size))

            # Verify archive integrity
            if tar -tzf "$pkg_file" >/dev/null 2>&1; then
                log_info "✓ Valid: $(basename "$pkg_file")"
            else
                log_error "✗ Corrupt: $(basename "$pkg_file")"
            fi
        fi
    done

    total_size_mb=$((total_size / 1024 / 1024))

    echo ""
    echo "========================================="
    echo "Package Creation Summary"
    echo "========================================="
    echo "Packages created: $package_count"
    echo "Total size: ${total_size_mb}MB"
    echo "Cache location: $LPM_CACHE"
    echo "Repository DB: $LPM_REPO_DB"
    echo "========================================="
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    log_info "=== CREATING BASE PACKAGES ==="

    # Create package cache directory
    mkdir -p "$LPM_CACHE"

    # Create packages for installed components
    log_info "Detecting installed components..."

    # Java Development
    if [ -d "/opt/jdk-"* ]; then
        log_info "Found Java installation"
    else
        log_warning "Java not found, skipping Java packages"
    fi

    if [ -d "/opt/maven" ]; then
        log_info "Found Maven installation"
    fi

    if [ -d "/opt/gradle" ]; then
        log_info "Found Gradle installation"
    fi

    if [ -d "/opt/tomcat" ]; then
        log_info "Found Tomcat installation"
    fi

    if [ -d "/opt/node" ]; then
        log_info "Found Node.js installation"
    fi

    if command -v docker &> /dev/null; then
        log_info "Found Docker installation"
    fi

    # Create packages
    echo ""
    # Package creation happens in the sections above

    # Create repository index
    create_repo_index

    # Create package list
    create_package_list

    # Verify packages
    verify_packages

    log_success "Base packages created successfully!"

    echo ""
    echo "To use these packages:"
    echo "  lpm list                    # List available packages"
    echo "  lpm install java            # Install Java package"
    echo "  lpm install maven           # Install Maven package"
    echo "  lpm info java               # Show package info"
    echo ""
    echo "Repository location: $LPM_REPO_DB"
    echo "Package cache: $LPM_CACHE"
}

# Run main function
main "$@"