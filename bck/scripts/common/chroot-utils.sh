#!/bin/bash
# Chroot environment utilities

source $(dirname $0)/utils.sh

# Prepare chroot environment
prepare_chroot() {
    log_info "Preparing chroot environment"

    # Create necessary directories
    mkdir -pv $LFS/{dev,proc,sys,run,etc,home,root,boot,lib64,usr,var}

    # Create essential device nodes
    if [ ! -c $LFS/dev/console ]; then
        mknod -m 600 $LFS/dev/console c 5 1
    fi

    if [ ! -c $LFS/dev/null ]; then
        mknod -m 666 $LFS/dev/null c 1 3
    fi

    # Mount virtual filesystems
    mount_virtual_kernel_filesystems

    # Copy DNS configuration
    cp -v /etc/resolv.conf $LFS/etc/

    log_info "Chroot environment prepared"
}

# Run command in chroot
run_in_chroot() {
    local cmd="$1"
    log_info "Running in chroot: $cmd"

    chroot "$LFS" /usr/bin/env -i \
        HOME=/root \
        TERM="$TERM" \
        PS1='(lfs chroot) \u:\w\$ ' \
        PATH=/usr/bin:/usr/sbin \
        MAKEFLAGS="-j${NUM_JOBS}" \
        LFS_TGT="${LFS_TGT}" \
        /bin/bash -c "$cmd"
}

# Copy host tools to chroot
copy_host_tools() {
    log_info "Copying host tools to chroot"

    local tools=(
        "/usr/bin/bash"
        "/usr/bin/cat"
        "/usr/bin/chmod"
        "/usr/bin/cp"
        "/usr/bin/grep"
        "/usr/bin/ln"
        "/usr/bin/ls"
        "/usr/bin/mkdir"
        "/usr/bin/mknod"
        "/usr/bin/mount"
        "/usr/bin/rm"
        "/usr/bin/sed"
        "/usr/bin/sh"
        "/usr/bin/sort"
        "/usr/bin/tar"
        "/usr/bin/umount"
        "/usr/bin/uniq"
        "/usr/bin/wc"
    )

    for tool in "${tools[@]}"; do
        if [ -f "$tool" ]; then
            cp -v "$tool" "$LFS${tool}"
        fi
    done
}

# Setup chroot user
setup_chroot_user() {
    local username=$1

    run_in_chroot "groupadd -g 1000 $username 2>/dev/null || true"
    run_in_chroot "useradd -u 1000 -g 1000 -G wheel,audio,video,storage -m $username 2>/dev/null || true"

    log_info "User $username created in chroot"
}

# Clean chroot
clean_chroot() {
    log_info "Cleaning chroot environment"

    # Unmount virtual filesystems
    umount_virtual_kernel_filesystems

    # Remove temporary files
    rm -rf $LFS/tmp/*
    rm -rf $LFS/var/tmp/*
    rm -rf $LFS/var/cache/*

    log_info "Chroot cleaned"
}

# Enter interactive chroot session
enter_interactive_chroot() {
    log_info "Entering interactive chroot session"
    log_info "Type 'exit' to leave"
    enter_chroot
}