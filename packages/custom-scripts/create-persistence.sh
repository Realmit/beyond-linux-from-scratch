#!/bin/bash
# Create persistence partition for LFS Live USB
# Allows saving changes between live sessions

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_success() { echo -e "${BLUE}[SUCCESS]${NC} $1"; }

# Default values
PERSISTENCE_SIZE=${1:-2048}  # Size in MB (default 2GB)
PERSISTENCE_LABEL="LFS-PERSIST"
PERSISTENCE_FS="ext4"

# ============================================================================
# SHOW HELP
# ============================================================================
show_help() {
    cat << 'EOF'
LFS Live USB Persistence Creator

Usage:
  create-persistence.sh [OPTIONS] [DEVICE]

Options:
  -s, --size SIZE    Persistence partition size in MB (default: 2048)
  -l, --label LABEL  Partition label (default: LFS-PERSIST)
  -f, --fs TYPE      Filesystem type: ext4, btrfs, xfs (default: ext4)
  -h, --help         Show this help message

Examples:
  # Create 4GB persistence on /dev/sdb
  sudo create-persistence.sh -s 4096 /dev/sdb

  # Create with custom label
  sudo create-persistence.sh -l MYSTORAGE /dev/sdc

  # Create using btrfs
  sudo create-persistence.sh -f btrfs /dev/sdd

Note:
  This script assumes the USB already has a bootable LFS ISO written to it.
  It will create a second partition for persistence without touching the first.
EOF
}

# ============================================================================
# CHECK DEPENDENCIES
# ============================================================================
check_dependencies() {
    local missing=()

    for cmd in parted lsblk mkfs.ext4 blkid; do
        if ! command -v $cmd &> /dev/null; then
            missing+=($cmd)
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing dependencies: ${missing[*]}"
        echo "Install with: apt install parted e2fsprogs util-linux"
        exit 1
    fi
}

# ============================================================================
# SELECT USB DEVICE
# ============================================================================
select_device() {
    if [ -n "$1" ]; then
        USB_DEV="$1"
        if [ ! -b "$USB_DEV" ]; then
            log_error "Device not found: $USB_DEV"
            exit 1
        fi
        return
    fi

    echo ""
    echo "========================================"
    echo "Available USB devices:"
    echo "========================================"

    # List USB devices
    lsblk -d -o NAME,SIZE,MODEL,TRAN | grep -E "usb|sd" || {
        log_error "No USB devices found"
        exit 1
    }

    echo ""
    read -p "Select USB device (e.g., sdb): " USB_NAME
    USB_DEV="/dev/$USB_NAME"

    if [ ! -b "$USB_DEV" ]; then
        log_error "Device not found: $USB_DEV"
        exit 1
    fi
}

# ============================================================================
# SHOW DEVICE INFORMATION
# ============================================================================
show_device_info() {
    echo ""
    echo "========================================"
    echo "Device Information:"
    echo "========================================"
    lsblk "$USB_DEV"

    echo ""
    echo "Partition layout:"
    parted "$USB_DEV" print 2>/dev/null || echo "No partition table"
}

# ============================================================================
# CHECK EXISTING PARTITIONS
# ============================================================================
check_existing_persistence() {
    # Check if persistence partition already exists
    local existing=$(blkid -L "$PERSISTENCE_LABEL" 2>/dev/null)
    if [ -n "$existing" ]; then
        log_warning "Persistence partition with label '$PERSISTENCE_LABEL' already exists: $existing"
        read -p "Remove existing persistence? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Remove the existing partition
            local dev_num=$(echo "$existing" | grep -oE '[0-9]+$')
            parted -s "$USB_DEV" rm "$dev_num"
            log_info "Removed existing persistence partition"
        else
            exit 0
        fi
    fi
}

# ============================================================================
# GET NEXT FREE PARTITION NUMBER
# ============================================================================
get_next_partition() {
    # Get highest partition number
    local max=0
    for part in $(lsblk -ln -o NAME "$USB_DEV" | grep "^${USB_DEV##*/}[0-9]" | sed "s/${USB_DEV##*/}//"); do
        if [ "$part" -gt "$max" ]; then
            max=$part
        fi
    done
    echo $((max + 1))
}

# ============================================================================
# GET FREE SPACE
# ============================================================================
get_free_space() {
    local sector_size=512
    local start_sector=$(parted -s "$USB_DEV" unit s print free | grep "Free Space" | tail -1 | awk '{print $1}' | sed 's/s//')
    local end_sector=$(parted -s "$USB_DEV" unit s print free | grep "Free Space" | tail -1 | awk '{print $2}' | sed 's/s//')

    if [ -z "$start_sector" ] || [ -z "$end_sector" ]; then
        # No free space found, use end of last partition
        local last_part=$(parted -s "$USB_DEV" print | grep -E "^ [0-9]" | tail -1 | awk '{print $3}' | sed 's/GB//g')
        start_sector=$(parted -s "$USB_DEV" unit s print | tail -2 | head -1 | awk '{print $3}' | sed 's/s//')
        end_sector="100%"
    fi

    echo "$start_sector $end_sector"
}

# ============================================================================
# CREATE PERSISTENCE PARTITION
# ============================================================================
create_persistence() {
    log_info "Creating persistence partition on $USB_DEV"
    log_info "Size: ${PERSISTENCE_SIZE}MB"
    log_info "Label: $PERSISTENCE_LABEL"
    log_info "Filesystem: $PERSISTENCE_FS"

    # Convert size to MB for parted
    local size_mb=$PERSISTENCE_SIZE

    # Get starting position
    local start_pos="${size_mb}MB"

    # Create partition
    log_info "Creating partition..."
    parted -s "$USB_DEV" mkpart primary "$PERSISTENCE_FS" "$start_pos" 100%

    # Wait for device to settle
    sleep 2
    partprobe "$USB_DEV" 2>/dev/null || true
    sleep 1

    # Find the new partition
    local part_num=$(get_next_partition)
    local PERSIST_PART="${USB_DEV}${part_num}"

    # Wait for partition to appear
    for i in $(seq 1 10); do
        if [ -b "$PERSIST_PART" ]; then
            break
        fi
        sleep 1
    done

    if [ ! -b "$PERSIST_PART" ]; then
        log_error "Partition not created: $PERSIST_PART"
        exit 1
    fi

    # Format the partition
    log_info "Formatting partition as $PERSISTENCE_FS..."
    case "$PERSISTENCE_FS" in
        ext4)
            mkfs.ext4 -F -L "$PERSISTENCE_LABEL" "$PERSIST_PART"
            ;;
        btrfs)
            mkfs.btrfs -f -L "$PERSISTENCE_LABEL" "$PERSIST_PART"
            ;;
        xfs)
            mkfs.xfs -f -L "$PERSISTENCE_LABEL" "$PERSIST_PART"
            ;;
        *)
            log_error "Unsupported filesystem: $PERSISTENCE_FS"
            exit 1
            ;;
    esac

    # Create overlay directories
    log_info "Setting up overlay directories..."
    mkdir -p /mnt/persist
    mount "$PERSIST_PART" /mnt/persist
    mkdir -p /mnt/persist/{upper,work}
    umount /mnt/persist

    log_success "Persistence partition created successfully!"
    echo ""
    echo "Partition: $PERSIST_PART"
    echo "Label: $PERSISTENCE_LABEL"
    echo "Size: ${PERSISTENCE_SIZE}MB"
    echo "Filesystem: $PERSISTENCE_FS"
}

# ============================================================================
# SHOW INSTRUCTIONS
# ============================================================================
show_instructions() {
    echo ""
    echo "========================================"
    echo "Persistence Setup Complete!"
    echo "========================================"
    echo ""
    echo "To use persistence when booting:"
    echo "  1. Boot from the USB drive"
    echo "  2. Select 'Try LFS Linux (with Persistence)' from the boot menu"
    echo "  3. Your changes will be saved automatically"
    echo ""
    echo "To check if persistence is working:"
    echo "  # After booting, look for persistence mount"
    echo "  mount | grep persistence"
    echo ""
    echo "To resize persistence later:"
    echo "  # WARNING: This will erase existing data!"
    echo "  sudo create-persistence.sh -s <new_size> $USB_DEV"
    echo ""
    echo "To backup persistence data:"
    echo "  sudo mount ${PERSIST_PART} /mnt"
    echo "  sudo rsync -av /mnt/ /backup/lfs-persistence/"
    echo "  sudo umount /mnt"
}

# ============================================================================
# REMOVE PERSISTENCE
# ============================================================================
remove_persistence() {
    log_warning "Removing persistence partition from $USB_DEV"

    # Find persistence partition
    local persist_part=$(blkid -L "$PERSISTENCE_LABEL" 2>/dev/null)

    if [ -z "$persist_part" ]; then
        log_error "No persistence partition found with label '$PERSISTENCE_LABEL'"
        exit 1
    fi

    local part_num=$(echo "$persist_part" | grep -oE '[0-9]+$')

    read -p "Remove partition $part_num? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        parted -s "$USB_DEV" rm "$part_num"
        log_success "Persistence partition removed"
    else
        log_info "Cancelled"
    fi
}

# ============================================================================
# RESIZE PERSISTENCE
# ============================================================================
resize_persistence() {
    log_info "Resizing persistence partition"

    local persist_part=$(blkid -L "$PERSISTENCE_LABEL" 2>/dev/null)
    if [ -z "$persist_part" ]; then
        log_error "No persistence partition found"
        exit 1
    fi

    local part_num=$(echo "$persist_part" | grep -oE '[0-9]+$')

    # Unmount if mounted
    umount "$persist_part" 2>/dev/null || true

    # Check filesystem first
    e2fsck -f "$persist_part"

    # Resize filesystem
    resize2fs "$persist_part" "${PERSISTENCE_SIZE}M"

    # Resize partition
    parted -s "$USB_DEV" resizepart "$part_num" 100%

    log_success "Persistence resized to ${PERSISTENCE_SIZE}MB"
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run as root (use sudo)"
        exit 1
    fi

    check_dependencies

    # Parse arguments
    local device=""
    local action="create"

    while [ $# -gt 0 ]; do
        case "$1" in
            -s|--size)
                PERSISTENCE_SIZE="$2"
                shift 2
                ;;
            -l|--label)
                PERSISTENCE_LABEL="$2"
                shift 2
                ;;
            -f|--fs)
                PERSISTENCE_FS="$2"
                shift 2
                ;;
            -r|--remove)
                action="remove"
                shift
                ;;
            --resize)
                action="resize"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                device="$1"
                shift
                ;;
        esac
    done

    select_device "$device"
    show_device_info

    case "$action" in
        remove)
            remove_persistence
            ;;
        resize)
            resize_persistence
            ;;
        create)
            check_existing_persistence
            create_persistence
            show_instructions
            ;;
    esac
}

main "$@"