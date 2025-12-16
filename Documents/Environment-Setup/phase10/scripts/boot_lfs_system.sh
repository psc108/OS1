#!/bin/bash
# Boot LFS System Script - Production Implementation
# SecureOS Phase 10: Automated OS Build System
set -euo pipefail

# Script metadata
SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/lfs_boot_$(date +%Y%m%d_%H%M%S).log"

# Configuration
LFS_SYSTEM_IMAGE="/tmp/secureos-lfs-system.tar.gz"
BOOT_METHOD="qemu"  # qemu, iso, vmdk
VM_MEMORY="2048"
VM_DISK_SIZE="8G"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Check if system image exists
check_system_image() {
    if [ ! -f "$LFS_SYSTEM_IMAGE" ]; then
        error_exit "LFS system image not found: $LFS_SYSTEM_IMAGE"
    fi
    log "Found LFS system image: $LFS_SYSTEM_IMAGE"
}

# Create bootable disk image
create_bootable_disk() {
    log "Creating bootable disk image..."
    
    local disk_image="/tmp/secureos-lfs-boot.img"
    
    # Create raw disk image
    qemu-img create -f raw "$disk_image" "$VM_DISK_SIZE" || error_exit "Failed to create disk image"
    
    # Setup loop device
    local loop_device=$(losetup --find --show "$disk_image")
    log "Using loop device: $loop_device"
    
    # Create partition table
    parted "$loop_device" --script mklabel msdos
    parted "$loop_device" --script mkpart primary ext4 1MiB 100%
    parted "$loop_device" --script set 1 boot on
    
    # Format partition
    mkfs.ext4 "${loop_device}p1" || error_exit "Failed to format partition"
    
    # Mount and extract system
    local mount_dir="/tmp/lfs-mount"
    mkdir -p "$mount_dir"
    mount "${loop_device}p1" "$mount_dir"
    
    log "Extracting LFS system to disk..."
    tar -xzf "$LFS_SYSTEM_IMAGE" -C "$mount_dir" || error_exit "Failed to extract system"
    
    # Install GRUB
    log "Installing GRUB bootloader..."
    grub-install --target=i386-pc --boot-directory="$mount_dir/boot" "$loop_device" || error_exit "GRUB installation failed"
    
    # Create GRUB configuration
    cat > "$mount_dir/boot/grub/grub.cfg" << 'EOF'
set timeout=10
set default=0

menuentry "SecureOS LFS" {
    set root=(hd0,1)
    linux /boot/vmlinuz root=/dev/sda1 ro
    initrd /boot/initrd.img
}

menuentry "SecureOS LFS (Recovery)" {
    set root=(hd0,1)
    linux /boot/vmlinuz root=/dev/sda1 ro single
    initrd /boot/initrd.img
}
EOF
    
    # Cleanup
    umount "$mount_dir"
    losetup -d "$loop_device"
    
    echo "$disk_image"
}

# Boot with QEMU
boot_with_qemu() {
    log "Booting LFS system with QEMU..."
    
    local disk_image="$1"
    
    # Check if QEMU is available
    command -v qemu-system-x86_64 >/dev/null || error_exit "QEMU not found"
    
    log "Starting QEMU virtual machine..."
    log "Memory: ${VM_MEMORY}MB"
    log "Disk: $disk_image"
    
    qemu-system-x86_64 \
        -m "$VM_MEMORY" \
        -hda "$disk_image" \
        -boot c \
        -enable-kvm \
        -cpu host \
        -smp 2 \
        -netdev user,id=net0 \
        -device e1000,netdev=net0 \
        -display gtk \
        -name "SecureOS LFS" || log "QEMU exited"
}

# Create ISO image
create_iso_image() {
    log "Creating bootable ISO image..."
    
    local iso_dir="/tmp/lfs-iso"
    local iso_output="/tmp/secureos-lfs.iso"
    
    mkdir -p "$iso_dir"
    
    # Extract system to ISO directory
    tar -xzf "$LFS_SYSTEM_IMAGE" -C "$iso_dir" || error_exit "Failed to extract system for ISO"
    
    # Create isolinux configuration
    mkdir -p "$iso_dir/isolinux"
    
    # Copy isolinux files (if available)
    if [ -f /usr/share/syslinux/isolinux.bin ]; then
        cp /usr/share/syslinux/isolinux.bin "$iso_dir/isolinux/"
        cp /usr/share/syslinux/ldlinux.c32 "$iso_dir/isolinux/" 2>/dev/null || true
    fi
    
    # Create isolinux configuration
    cat > "$iso_dir/isolinux/isolinux.cfg" << 'EOF'
DEFAULT secureos
TIMEOUT 100
PROMPT 1

LABEL secureos
    KERNEL /boot/vmlinuz
    APPEND initrd=/boot/initrd.img root=/dev/sr0 ro
    
LABEL recovery
    KERNEL /boot/vmlinuz
    APPEND initrd=/boot/initrd.img root=/dev/sr0 ro single
EOF
    
    # Create ISO
    if command -v xorriso >/dev/null; then
        xorriso -as mkisofs \
            -iso-level 3 \
            -full-iso9660-filenames \
            -volid "SecureOS-LFS" \
            -eltorito-boot isolinux/isolinux.bin \
            -eltorito-catalog isolinux/boot.cat \
            -no-emul-boot \
            -boot-load-size 4 \
            -boot-info-table \
            -output "$iso_output" \
            "$iso_dir" || error_exit "ISO creation failed"
    else
        log "WARNING: xorriso not available, ISO creation skipped"
        return 1
    fi
    
    log "ISO image created: $iso_output"
    echo "$iso_output"
}

# Create VMDK image
create_vmdk_image() {
    log "Creating VMDK image..."
    
    local raw_image="$1"
    local vmdk_output="/tmp/secureos-lfs.vmdk"
    
    # Convert to VMDK format
    qemu-img convert -f raw -O vmdk "$raw_image" "$vmdk_output" || error_exit "VMDK conversion failed"
    
    log "VMDK image created: $vmdk_output"
    echo "$vmdk_output"
}

# Display boot options
show_boot_options() {
    cat << 'EOF'
SecureOS LFS Boot Options:

1. QEMU Virtual Machine (Recommended)
   - Boots directly in QEMU with KVM acceleration
   - Requires: qemu-system-x86_64

2. ISO Image
   - Creates bootable ISO for CD/DVD or USB
   - Requires: xorriso

3. VMDK Image
   - Creates VMware-compatible disk image
   - Requires: qemu-img

4. Raw Disk Image
   - Creates raw disk image for direct use

Enter your choice (1-4):
EOF
}

# Interactive boot menu
interactive_boot() {
    show_boot_options
    read -r choice
    
    case "$choice" in
        1)
            log "Selected: QEMU Virtual Machine"
            local disk_image=$(create_bootable_disk)
            boot_with_qemu "$disk_image"
            ;;
        2)
            log "Selected: ISO Image"
            create_iso_image
            ;;
        3)
            log "Selected: VMDK Image"
            local disk_image=$(create_bootable_disk)
            create_vmdk_image "$disk_image"
            ;;
        4)
            log "Selected: Raw Disk Image"
            create_bootable_disk
            ;;
        *)
            error_exit "Invalid choice: $choice"
            ;;
    esac
}

# Main execution
main() {
    log "Starting LFS system boot - Version $SCRIPT_VERSION"
    
    check_system_image
    
    if [ $# -eq 0 ]; then
        interactive_boot
    else
        case "$1" in
            --qemu)
                local disk_image=$(create_bootable_disk)
                boot_with_qemu "$disk_image"
                ;;
            --iso)
                create_iso_image
                ;;
            --vmdk)
                local disk_image=$(create_bootable_disk)
                create_vmdk_image "$disk_image"
                ;;
            --raw)
                create_bootable_disk
                ;;
            --help)
                echo "Usage: $0 [--qemu|--iso|--vmdk|--raw|--help]"
                echo "  --qemu  Boot in QEMU virtual machine"
                echo "  --iso   Create bootable ISO image"
                echo "  --vmdk  Create VMware VMDK image"
                echo "  --raw   Create raw disk image"
                echo "  --help  Show this help"
                exit 0
                ;;
            *)
                error_exit "Unknown option: $1"
                ;;
        esac
    fi
    
    log "Boot process completed"
}

# Execute main function
main "$@"