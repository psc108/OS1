#!/bin/bash
# Generate VMware VMDK Image for SecureOS
# Uses qemu-img for VMDK creation with bootloader installation
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Parse command line arguments
SOURCE=""
OUTPUT=""
SIZE="8G"

while [[ $# -gt 0 ]]; do
    case $1 in
        --source=*)
            SOURCE="${1#*=}"
            shift
            ;;
        --output=*)
            OUTPUT="${1#*=}"
            shift
            ;;
        --size=*)
            SIZE="${1#*=}"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

[[ -z "$SOURCE" ]] && { echo "ERROR: Source is required (lfs|rocky)"; exit 1; }
[[ -z "$OUTPUT" ]] && { echo "ERROR: Output path is required"; exit 1; }

# Source LFS environment if building LFS VMDK
if [[ "$SOURCE" == "lfs" ]]; then
    if [[ -f ~/.lfs_env ]]; then
        source ~/.lfs_env
    else
        echo "ERROR: LFS environment not configured for LFS build"
        exit 1
    fi
fi

log "Generating $SOURCE-based SecureOS VMDK image..."
log "Output: $OUTPUT"
log "Size: $SIZE"

# Determine source directory
case "$SOURCE" in
    lfs)
        SOURCE_DIR="$LFS"
        [[ -z "$SOURCE_DIR" || ! -d "$SOURCE_DIR" ]] && { echo "ERROR: LFS build not found"; exit 1; }
        ;;
    rocky)
        SOURCE_DIR="/tmp/rocky-secureos-build"
        [[ ! -d "$SOURCE_DIR" ]] && { echo "ERROR: Rocky build not found"; exit 1; }
        ;;
    *)
        echo "ERROR: Invalid source: $SOURCE"
        exit 1
        ;;
esac

# Temporary files
RAW_IMAGE="/tmp/secureos-raw-$$.img"
LOOP_DEVICE=""

# Cleanup function
cleanup() {
    log "Cleaning up temporary files..."
    if [[ -n "$LOOP_DEVICE" ]]; then
        umount "${LOOP_DEVICE}p1" 2>/dev/null || true
        umount "${LOOP_DEVICE}p2" 2>/dev/null || true
        losetup -d "$LOOP_DEVICE" 2>/dev/null || true
    fi
    rm -f "$RAW_IMAGE"
}
trap cleanup EXIT

# Create raw disk image
create_raw_image() {
    log "Creating raw disk image ($SIZE)..."
    
    # Create raw image
    qemu-img create -f raw "$RAW_IMAGE" "$SIZE" || {
        echo "ERROR: Failed to create raw image"
        exit 1
    }
    
    log "✅ Raw image created"
}

# Setup partitions
setup_partitions() {
    log "Setting up disk partitions..."
    
    # Setup loop device
    LOOP_DEVICE=$(losetup --find --show "$RAW_IMAGE")
    log "Using loop device: $LOOP_DEVICE"
    
    # Create partition table
    parted "$LOOP_DEVICE" --script mklabel gpt || {
        echo "ERROR: Failed to create partition table"
        exit 1
    }
    
    # Create EFI system partition (100MB)
    parted "$LOOP_DEVICE" --script mkpart ESP fat32 1MiB 100MiB || {
        echo "ERROR: Failed to create EFI partition"
        exit 1
    }
    
    parted "$LOOP_DEVICE" --script set 1 esp on || {
        echo "ERROR: Failed to set ESP flag"
        exit 1
    }
    
    # Create root partition (remaining space)
    parted "$LOOP_DEVICE" --script mkpart primary ext4 100MiB 100% || {
        echo "ERROR: Failed to create root partition"
        exit 1
    }
    
    # Inform kernel of partition changes
    partprobe "$LOOP_DEVICE"
    sleep 2
    
    log "✅ Partitions created"
}

# Format partitions
format_partitions() {
    log "Formatting partitions..."
    
    # Format EFI partition
    mkfs.fat -F32 "${LOOP_DEVICE}p1" || {
        echo "ERROR: Failed to format EFI partition"
        exit 1
    }
    
    # Format root partition
    mkfs.ext4 -F "${LOOP_DEVICE}p2" || {
        echo "ERROR: Failed to format root partition"
        exit 1
    }
    
    log "✅ Partitions formatted"
}

# Install system
install_system() {
    log "Installing SecureOS system to VMDK..."
    
    MOUNT_DIR="/tmp/secureos-vmdk-mount-$$"
    mkdir -p "$MOUNT_DIR"
    
    # Mount root partition
    mount "${LOOP_DEVICE}p2" "$MOUNT_DIR" || {
        echo "ERROR: Failed to mount root partition"
        exit 1
    }
    
    # Create EFI mount point and mount
    mkdir -p "$MOUNT_DIR/boot/efi"
    mount "${LOOP_DEVICE}p1" "$MOUNT_DIR/boot/efi" || {
        echo "ERROR: Failed to mount EFI partition"
        umount "$MOUNT_DIR"
        exit 1
    }
    
    # Copy system files
    log "Copying system files..."
    cp -a "$SOURCE_DIR"/* "$MOUNT_DIR/" || {
        echo "ERROR: Failed to copy system files"
        umount "$MOUNT_DIR/boot/efi"
        umount "$MOUNT_DIR"
        exit 1
    }
    
    # Update fstab for VMDK
    cat > "$MOUNT_DIR/etc/fstab" << 'EOF'
# SecureOS VMDK fstab
UUID=ROOT_UUID /               ext4    defaults            1 1
UUID=EFI_UUID  /boot/efi       vfat    defaults            0 2
proc           /proc           proc    nosuid,noexec,nodev 0 0
sysfs          /sys            sysfs   nosuid,noexec,nodev 0 0
devpts         /dev/pts        devpts  gid=5,mode=620      0 0
tmpfs          /run            tmpfs   defaults            0 0
devtmpfs       /dev            devtmpfs mode=0755,nosuid   0 0
EOF
    
    # Get UUIDs and update fstab
    ROOT_UUID=$(blkid -s UUID -o value "${LOOP_DEVICE}p2")
    EFI_UUID=$(blkid -s UUID -o value "${LOOP_DEVICE}p1")
    
    sed -i "s/ROOT_UUID/$ROOT_UUID/g" "$MOUNT_DIR/etc/fstab"
    sed -i "s/EFI_UUID/$EFI_UUID/g" "$MOUNT_DIR/etc/fstab"
    
    log "✅ System installed to VMDK"
    
    # Install bootloader
    install_bootloader "$MOUNT_DIR" "$ROOT_UUID"
    
    # Unmount filesystems
    umount "$MOUNT_DIR/boot/efi"
    umount "$MOUNT_DIR"
    rmdir "$MOUNT_DIR"
}

# Install GRUB bootloader
install_bootloader() {
    local mount_dir="$1"
    local root_uuid="$2"
    
    log "Installing GRUB bootloader..."
    
    # Install GRUB for UEFI
    if command -v grub-install >/dev/null 2>&1; then
        grub-install --target=x86_64-efi \
                     --efi-directory="$mount_dir/boot/efi" \
                     --boot-directory="$mount_dir/boot" \
                     --bootloader-id=SecureOS \
                     --removable || {
            log "WARNING: GRUB UEFI installation failed, trying alternative method"
            
            # Alternative: manual EFI installation
            mkdir -p "$mount_dir/boot/efi/EFI/BOOT"
            if [[ -f /boot/efi/EFI/*/grubx64.efi ]]; then
                cp /boot/efi/EFI/*/grubx64.efi "$mount_dir/boot/efi/EFI/BOOT/bootx64.efi"
            fi
        }
    fi
    
    # Create GRUB configuration
    mkdir -p "$mount_dir/boot/grub"
    cat > "$mount_dir/boot/grub/grub.cfg" << EOF
# SecureOS GRUB Configuration for VMDK
set timeout=10
set default=0

menuentry "SecureOS (Security Hardened)" {
    search --set=root --fs-uuid $root_uuid
    linux /boot/vmlinuz root=UUID=$root_uuid ro security=secureos lsm=secureos,selinux audit=1
    initrd /boot/initrd.img
}

menuentry "SecureOS (Recovery Mode)" {
    search --set=root --fs-uuid $root_uuid
    linux /boot/vmlinuz root=UUID=$root_uuid ro single
    initrd /boot/initrd.img
}
EOF
    
    # Ensure kernel and initrd exist
    if [[ ! -f "$mount_dir/boot/vmlinuz" ]]; then
        # Copy kernel from source or host
        if [[ -f "$SOURCE_DIR/boot/vmlinuz" ]]; then
            cp "$SOURCE_DIR/boot/vmlinuz" "$mount_dir/boot/"
        elif [[ -f "/boot/vmlinuz-$(uname -r)" ]]; then
            cp "/boot/vmlinuz-$(uname -r)" "$mount_dir/boot/vmlinuz"
            log "WARNING: Using host kernel"
        fi
    fi
    
    if [[ ! -f "$mount_dir/boot/initrd.img" ]]; then
        # Create minimal initrd
        create_minimal_initrd "$mount_dir/boot/initrd.img"
    fi
    
    log "✅ Bootloader installed"
}

# Create minimal initrd
create_minimal_initrd() {
    local initrd_path="$1"
    
    log "Creating minimal initrd..."
    
    INITRD_DIR="/tmp/vmdk-initrd-$$"
    mkdir -p "$INITRD_DIR"/{bin,sbin,etc,proc,sys,dev,run,lib,lib64}
    
    # Copy essential binaries
    cp /bin/bash "$INITRD_DIR/bin/" 2>/dev/null || cp /usr/bin/bash "$INITRD_DIR/bin/"
    ln -s bash "$INITRD_DIR/bin/sh"
    
    # Create init script
    cat > "$INITRD_DIR/init" << 'INIT_EOF'
#!/bin/bash
# Minimal init for VMDK boot
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

# Wait for root device
sleep 2

# Mount root filesystem
mkdir -p /newroot
mount /dev/sda2 /newroot 2>/dev/null || mount /dev/vda2 /newroot

# Switch to real root
exec switch_root /newroot /sbin/init
INIT_EOF
    
    chmod +x "$INITRD_DIR/init"
    
    # Copy required libraries
    ldd "$INITRD_DIR/bin/bash" 2>/dev/null | grep -o '/lib[^ ]*' | while read lib; do
        if [[ -f "$lib" ]]; then
            cp "$lib" "$INITRD_DIR/lib/" 2>/dev/null || true
        fi
    done
    
    # Create initrd
    cd "$INITRD_DIR"
    find . | cpio -o -H newc | gzip > "$initrd_path"
    cd - > /dev/null
    
    rm -rf "$INITRD_DIR"
    
    log "✅ Minimal initrd created"
}

# Convert to VMDK format
convert_to_vmdk() {
    log "Converting to VMDK format..."
    
    # Convert raw image to VMDK
    qemu-img convert -f raw -O vmdk "$RAW_IMAGE" "$OUTPUT" || {
        echo "ERROR: Failed to convert to VMDK format"
        exit 1
    }
    
    log "✅ VMDK conversion completed"
}

# Validate VMDK
validate_vmdk() {
    log "Validating VMDK image..."
    
    # Check if file exists and is not empty
    if [[ ! -f "$OUTPUT" || ! -s "$OUTPUT" ]]; then
        echo "ERROR: Generated VMDK is empty or missing"
        exit 1
    fi
    
    # Check file type
    if ! qemu-img info "$OUTPUT" | grep -q "vmdk"; then
        echo "ERROR: Generated file is not a valid VMDK"
        exit 1
    fi
    
    # Calculate checksum
    sha256sum "$OUTPUT" > "${OUTPUT}.sha256"
    
    log "✅ VMDK validation completed"
    log "   File: $OUTPUT"
    log "   Size: $(du -h "$OUTPUT" | cut -f1)"
    log "   SHA256: $(cat "${OUTPUT}.sha256" | cut -d' ' -f1)"
}

# Main execution
main() {
    log "Starting SecureOS VMDK generation"
    log "Source: $SOURCE"
    log "Output: $OUTPUT"
    log "Size: $SIZE"
    
    # Check dependencies
    command -v qemu-img >/dev/null || { echo "ERROR: qemu-img not found"; exit 1; }
    command -v parted >/dev/null || { echo "ERROR: parted not found"; exit 1; }
    
    # Create output directory if needed
    mkdir -p "$(dirname "$OUTPUT")"
    
    # Generate VMDK
    create_raw_image
    setup_partitions
    format_partitions
    install_system
    convert_to_vmdk
    validate_vmdk
    
    log "✅ SecureOS VMDK generation completed successfully"
}

# Execute main function
main "$@"