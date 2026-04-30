#!/bin/bash
# Check host system requirements

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/utils.sh"
source "$SCRIPT_DIR/../common/error-handler.sh"

setup_error_handling

# Skip all checks if running in Docker
if [ -f /.dockerenv ]; then
    log_info "Running in Docker container - skipping host system checks"
    exit 0
fi

log_info "Checking host system requirements"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "Please run as root"
    exit 1
fi

# Check distribution
if [ -f /etc/os-release ]; then
    . /etc/os-release
    log_info "Distribution: $NAME $VERSION"
fi

# Check architecture
ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ]; then
    log_warning "Architecture is $ARCH, LFS requires x86_64"
fi

# Check required commands
required_commands=(
    "bash" "gcc" "g++" "ld" "bison" "flex" "gawk" "m4"
    "make" "patch" "sed" "tar" "texinfo" "xz" "grep" "awk"
    "wget" "python3" "git" "rsync" "parted" "xorriso"
)

missing_commands=()
for cmd in "${required_commands[@]}"; do
    if ! command -v $cmd &> /dev/null; then
        missing_commands+=($cmd)
    fi
done

if [ ${#missing_commands[@]} -ne 0 ]; then
    log_error "Missing required commands: ${missing_commands[*]}"
    exit 1
fi

# Check library versions
check_version() {
    local cmd=$1
    local min_version=$2
    local version=$($cmd --version 2>&1 | head -n1 | grep -oE '[0-9]+\.[0-9]+\.?[0-9]*' | head -n1)

    if [ -z "$version" ]; then
        log_warning "Could not determine version for $cmd"
        return 0
    fi

    if [ "$(echo -e "$version\n$min_version" | sort -V | head -n1)" != "$min_version" ]; then
        log_error "$cmd version $version is too old (need >= $min_version)"
        return 1
    fi

    log_info "$cmd version $version OK"
    return 0
}

# Check critical versions
critical_versions=(
    "gcc:12.0"
    "make:4.0"
    "bash:3.2"
    "bison:2.7"
)

for item in "${critical_versions[@]}"; do
    cmd="${item%:*}"
    min="${item#*:}"
    check_version "$cmd" "$min" || exit 1
done

# Check kernel version
kernel_version=$(uname -r)
log_info "Kernel version: $kernel_version"

# Check disk space
available_space=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "$available_space" -lt 50 ]; then
    log_error "Insufficient disk space: ${available_space}GB available, need 50GB"
    exit 1
fi

# Check memory
total_mem=$(free -g | awk '/^Mem:/{print $2}')
if [ "$total_mem" -lt 8 ]; then
    log_warning "Low memory: ${total_mem}GB (recommended: 8GB+)"
fi

# Check CPU cores
cpu_cores=$(nproc)
log_info "CPU cores: $cpu_cores"

log_info "Host system check passed!"