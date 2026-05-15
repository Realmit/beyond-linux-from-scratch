#!/bin/bash
# Error handling utilities

# Error trap function
error_trap() {
    local line=$1
    local command=$2
    local code=$3

    log_error "Command failed at line $line: $command"
    log_error "Exit code: $code"

    # Log system state
    log_error "=== System State ==="
    log_error "PWD: $(pwd)"
    log_error "LFS: ${LFS:-not set}"
    log_error "PATH: $PATH"

    # Check disk space
    local disk_usage=$(df -h ${LFS:-/} 2>/dev/null || df -h /)
    log_error "Disk usage: $disk_usage"

    # Check memory
    local mem_info=$(free -h 2>/dev/null || echo "Memory info not available")
    log_error "Memory: $mem_info"

    # Create error report
    local error_report="/tmp/lfs-error-$(date +%Y%m%d-%H%M%S).log"
    cat > $error_report << EOF
LFS Build Error Report
======================
Timestamp: $(date)
Line: $line
Command: $command
Exit code: $code

Environment:
LFS=$LFS
LFS_TGT=$LFS_TGT
MAKEFLAGS=$MAKEFLAGS

Last 50 lines of build log:
$(tail -50 /lfs-build/build.log 2>/dev/null || echo "No build log")

System Info:
$(uname -a)
EOF

    log_error "Error report saved to: $error_report"

    # Cleanup on error
    if [ "${LFS_CLEANUP_ON_ERROR:-yes}" = "yes" ]; then
        log_warning "Cleaning up partial build..."
        cleanup_partial_build
    fi

    exit $code
}

# Partial build cleanup
cleanup_partial_build() {
    if [ -n "$LFS" ] && [ -d "$LFS" ]; then
        log_info "Unmounting filesystems..."
        umount -l $LFS/dev/pts 2>/dev/null || true
        umount -l $LFS/dev 2>/dev/null || true
        umount -l $LFS/proc 2>/dev/null || true
        umount -l $LFS/sys 2>/dev/null || true
        umount -l $LFS/run 2>/dev/null || true
    fi
}

# Retry command on failure
retry() {
    local max_attempts=${1:-3}
    local delay=${2:-5}
    shift 2

    local attempt=1
    local exit_code=0

    while [ $attempt -le $max_attempts ]; do
        log_info "Attempt $attempt of $max_attempts: $@"

        if "$@"; then
            return 0
        else
            exit_code=$?
            log_warning "Command failed (attempt $attempt)"

            if [ $attempt -eq $max_attempts ]; then
                log_error "Command failed after $max_attempts attempts"
                return $exit_code
            fi

            sleep $delay
            ((attempt++))
        fi
    done
}

# Check build prerequisites with retry
check_with_retry() {
    local check_cmd=$1
    local max_retries=${2:-5}

    retry $max_retries 10 "$check_cmd"
}

# Validate build environment
validate_build_env() {
    local errors=0

    # Check required variables
    for var in LFS LFS_TGT NUM_JOBS; do
        if [ -z "${!var}" ]; then
            log_error "Required variable $var is not set"
            ((errors++))
        fi
    done

    # Check required directories
    for dir in /sources $LFS; do
        if [ ! -d "$dir" ]; then
            log_error "Required directory $dir does not exist"
            ((errors++))
        fi
    done

    # Check available disk space (need at least 10GB free)
    local free_space=$(df --output=avail "$LFS" | tail -1)
    if [ "$free_space" -lt 10485760 ]; then  # 10GB in KB
        log_error "Insufficient disk space in $LFS (need at least 10GB)"
        ((errors++))
    fi

    if [ $errors -gt 0 ]; then
        log_error "Build environment validation failed with $errors errors"
        return 1
    fi

    log_info "Build environment validated successfully"
    return 0
}

# Setup error handling
setup_error_handling() {
    set -E
    trap 'error_trap ${LINENO} "$BASH_COMMAND" $?' ERR

    # Set default cleanup behavior
    export LFS_CLEANUP_ON_ERROR=${LFS_CLEANUP_ON_ERROR:-yes}
}

# Safe source file with error handling
safe_source() {
    local file=$1

    if [ ! -f "$file" ]; then
        log_error "Cannot source: $file does not exist"
        return 1
    fi

    source "$file"
    log_info "Successfully sourced $file"
}

# Export functions
export -f error_trap cleanup_partial_build retry check_with_retry validate_build_env setup_error_handling safe_source