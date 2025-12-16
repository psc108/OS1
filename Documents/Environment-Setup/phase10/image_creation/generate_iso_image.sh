#!/bin/bash
# Generate Bootable SecureOS ISO Image
# Uses Phase 8 deployment patterns with GRUB bootloader
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Parse command line arguments
SOURCE=""
OUTPUT=""
HYBRID_BOOT=false

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
        --hybrid-boot)
            HYBRID_BOOT=true
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

# Source LFS environment if building LFS ISO
if [[ "$SOURCE" == "lfs" ]]; then
    if [[ -f ~/.lfs_env ]]; then
        source ~/.lfs_env
    else
        echo "ERROR: LFS environment not configured for LFS build"
        exit 1
    fi
fi

log "Generating $SOURCE-based SecureOS ISO image..."
log "Output: $OUTPUT"
log "Hybrid boot: $HYBRID_BOOT"

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

# Create ISO build directory
ISO_BUILD_DIR="/tmp/secureos-iso-$$"
mkdir -p "$ISO_BUILD_DIR"

# Cleanup function
cleanup() {
    log "Cleaning up temporary files..."
    rm -rf "$ISO_BUILD_DIR"
}
trap cleanup EXIT

# Copy system files to ISO directory
copy_system_files() {
    log "Copying system files to ISO directory..."
    
    # Copy the built system
    cp -a "$SOURCE_DIR"/* "$ISO_BUILD_DIR/" || {
        echo "ERROR: Failed to copy system files"
        exit 1
    }
    
    # Create ISO-specific directories
    mkdir -p "$ISO_BUILD_DIR"/{isolinux,EFI/BOOT}
    
    log "✅ System files copied"
}

# Setup GRUB bootloader
setup_grub_bootloader() {
    log "Setting up GRUB bootloader..."
    
    # Install syslinux for BIOS boot (if available)
    if command -v syslinux >/dev/null 2>&1; then
        # Copy syslinux files
        cp /usr/share/syslinux/isolinux.bin "$ISO_BUILD_DIR/isolinux/" 2>/dev/null || {
            # Alternative location
            cp /usr/lib/syslinux/isolinux.bin "$ISO_BUILD_DIR/isolinux/" 2>/dev/null || {
                log "WARNING: isolinux.bin not found, BIOS boot may not work"
            }
        }
        
        cp /usr/share/syslinux/ldlinux.c32 "$ISO_BUILD_DIR/isolinux/" 2>/dev/null || true
        cp /usr/share/syslinux/libcom32.c32 "$ISO_BUILD_DIR/isolinux/" 2>/dev/null || true
        cp /usr/share/syslinux/libutil.c32 "$ISO_BUILD_DIR/isolinux/" 2>/dev/null || true
        cp /usr/share/syslinux/menu.c32 "$ISO_BUILD_DIR/isolinux/" 2>/dev/null || true
    fi
    
    # Create isolinux configuration
    cat > "$ISO_BUILD_DIR/isolinux/isolinux.cfg" << 'EOF'
DEFAULT menu.c32
PROMPT 0
TIMEOUT 100

MENU TITLE SecureOS Boot Menu

LABEL secureos
    MENU LABEL SecureOS (Security Hardened)
    KERNEL /boot/vmlinuz
    APPEND initrd=/boot/initrd.img root=live:CDLABEL=SecureOS rd.live.image quiet security=secureos

LABEL recovery
    MENU LABEL SecureOS (Recovery Mode)
    KERNEL /boot/vmlinuz
    APPEND initrd=/boot/initrd.img root=live:CDLABEL=SecureOS rd.live.image single
EOF
    
    # Setup UEFI boot
    if command -v grub-mkimage >/dev/null 2>&1; then
        # Create GRUB EFI image
        grub-mkimage -O x86_64-efi -o "$ISO_BUILD_DIR/EFI/BOOT/bootx64.efi" \
            part_gpt part_msdos fat ext2 normal boot linux multiboot iso9660 configfile search search_label || {
            log "WARNING: Failed to create GRUB EFI image"
        }
        
        # Create GRUB configuration for EFI
        mkdir -p "$ISO_BUILD_DIR/boot/grub"
        cat > "$ISO_BUILD_DIR/boot/grub/grub.cfg" << 'EOF'
set timeout=10
set default=0

menuentry "SecureOS (Security Hardened)" {
    linux /boot/vmlinuz root=live:CDLABEL=SecureOS rd.live.image quiet security=secureos lsm=secureos,selinux
    initrd /boot/initrd.img
}

menuentry "SecureOS (Recovery Mode)" {
    linux /boot/vmlinuz root=live:CDLABEL=SecureOS rd.live.image single
    initrd /boot/initrd.img
}
EOF
    fi
    
    log "✅ GRUB bootloader configured"
}

# Create kernel and initrd for live boot
create_live_boot() {
    log "Creating live boot components..."
    
    # Find kernel in the built system
    KERNEL_PATH=""
    if [[ -f "$SOURCE_DIR/boot/vmlinuz" ]]; then
        KERNEL_PATH="$SOURCE_DIR/boot/vmlinuz"
    elif [[ -f "$SOURCE_DIR/boot/vmlinuz-"* ]]; then
        KERNEL_PATH=$(ls "$SOURCE_DIR/boot/vmlinuz-"* | head -1)
    else
        # Use host kernel as fallback
        KERNEL_PATH="/boot/vmlinuz-$(uname -r)"
        log "WARNING: Using host kernel as fallback"
    fi
    
    # Copy kernel
    mkdir -p "$ISO_BUILD_DIR/boot"
    cp "$KERNEL_PATH" "$ISO_BUILD_DIR/boot/vmlinuz" || {
        echo "ERROR: Failed to copy kernel"
        exit 1
    }
    
    # Create initrd for live boot
    create_live_initrd
    
    log "✅ Live boot components created"
}

# Create live initrd
create_live_initrd() {
    log "Creating live initrd..."
    
    INITRD_DIR="/tmp/secureos-initrd-$$"
    mkdir -p "$INITRD_DIR"
    
    # Create directory structure
    mkdir -p "$INITRD_DIR"/{bin,sbin,etc,proc,sys,dev,run,usr/{bin,sbin},lib,lib64,mnt,tmp}
    
    # Copy essential binaries
    cp /bin/bash "$INITRD_DIR/bin/" 2>/dev/null || cp /usr/bin/bash "$INITRD_DIR/bin/"
    cp /bin/sh "$INITRD_DIR/bin/" 2>/dev/null || ln -s bash "$INITRD_DIR/bin/sh"
    cp /sbin/init "$INITRD_DIR/sbin/" 2>/dev/null || cp /usr/sbin/init "$INITRD_DIR/sbin/" 2>/dev/null || {
        # Create minimal init
        cat > "$INITRD_DIR/sbin/init" << 'INIT_EOF'
#!/bin/bash
# SecureOS Live Boot Init
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

# Find and mount the live filesystem
for device in /dev/sr* /dev/scd*; do
    if [[ -b "$device" ]]; then
        mkdir -p /mnt/live
        if mount -t iso9660 "$device" /mnt/live 2>/dev/null; then
            if [[ -d /mnt/live/LiveOS ]]; then
                # Mount squashfs if available
                if [[ -f /mnt/live/LiveOS/squashfs.img ]]; then
                    mkdir -p /mnt/squash
                    mount -t squashfs /mnt/live/LiveOS/squashfs.img /mnt/squash
                    # Switch root to live system
                    exec switch_root /mnt/squash /sbin/init
                fi
            fi
            # Direct boot from ISO
            exec switch_root /mnt/live /sbin/init
        fi
    fi
done

# Fallback to emergency shell
echo "Failed to find live filesystem"
exec /bin/bash
INIT_EOF
        chmod +x "$INITRD_DIR/sbin/init"
    }
    
    # Copy required libraries
    copy_libs() {
        local binary="$1"
        ldd "$binary" 2>/dev/null | grep -o '/lib[^ ]*' | while read lib; do
            if [[ -f "$lib" ]]; then
                mkdir -p "$INITRD_DIR/$(dirname "$lib")"
                cp "$lib" "$INITRD_DIR/$lib" 2>/dev/null || true
            fi
        done
    }
    
    copy_libs "$INITRD_DIR/bin/bash"
    copy_libs "$INITRD_DIR/sbin/init"
    
    # Create initrd archive
    cd "$INITRD_DIR"
    find . | cpio -o -H newc | gzip > "$ISO_BUILD_DIR/boot/initrd.img"
    cd - > /dev/null
    
    # Cleanup
    rm -rf "$INITRD_DIR"
    
    log "✅ Live initrd created"
}

# Generate ISO image
generate_iso() {
    log "Generating ISO image..."
    
    # Determine ISO generation tool
    if command -v xorriso >/dev/null 2>&1; then
        ISO_TOOL="xorriso"
    elif command -v genisoimage >/dev/null 2>&1; then
        ISO_TOOL="genisoimage"
    elif command -v mkisofs >/dev/null 2>&1; then
        ISO_TOOL="mkisofs"
    else
        echo "ERROR: No ISO generation tool found (xorriso, genisoimage, or mkisofs required)"
        exit 1
    fi
    
    log "Using ISO tool: $ISO_TOOL"
    
    case "$ISO_TOOL" in
        xorriso)
            if [[ "$HYBRID_BOOT" == "true" ]]; then
                # Hybrid bootable ISO (UEFI + BIOS)
                xorriso -as mkisofs \
                    -iso-level 3 \
                    -full-iso9660-filenames \
                    -volid "SecureOS" \
                    -appid "SecureOS Security-First Operating System" \
                    -publisher "SecureOS Project" \
                    -preparer "SecureOS Build System" \
                    -eltorito-boot isolinux/isolinux.bin \
                    -eltorito-catalog isolinux/boot.cat \
                    -no-emul-boot \
                    -boot-load-size 4 \
                    -boot-info-table \
                    -eltorito-alt-boot \
                    -e EFI/BOOT/bootx64.efi \
                    -no-emul-boot \
                    -isohybrid-gpt-basdat \
                    -output "$OUTPUT" \
                    "$ISO_BUILD_DIR" || {
                    echo "ERROR: ISO generation failed"
                    exit 1
                }
            else
                # Simple ISO
                xorriso -as mkisofs \
                    -volid "SecureOS" \
                    -output "$OUTPUT" \
                    "$ISO_BUILD_DIR" || {
                    echo "ERROR: ISO generation failed"
                    exit 1
                }
            fi
            ;;
        genisoimage|mkisofs)
            $ISO_TOOL -o "$OUTPUT" \
                -b isolinux/isolinux.bin \
                -c isolinux/boot.cat \
                -no-emul-boot \
                -boot-load-size 4 \
                -boot-info-table \
                -V "SecureOS" \
                -R -J \
                "$ISO_BUILD_DIR" || {
                echo "ERROR: ISO generation failed"
                exit 1
            }
            ;;
    esac
    
    log "✅ ISO image generated successfully"
}

# Validate ISO
validate_iso() {
    log "Validating ISO image..."
    
    # Check if file exists and is not empty
    if [[ ! -f "$OUTPUT" || ! -s "$OUTPUT" ]]; then
        echo "ERROR: Generated ISO is empty or missing"
        exit 1
    fi
    
    # Check file type
    if ! file "$OUTPUT" | grep -q "ISO 9660"; then
        echo "ERROR: Generated file is not a valid ISO"
        exit 1
    fi
    
    # Calculate and store checksum
    sha256sum "$OUTPUT" > "${OUTPUT}.sha256"
    
    log "✅ ISO validation completed"
    log "   File: $OUTPUT"
    log "   Size: $(du -h "$OUTPUT" | cut -f1)"
    log "   SHA256: $(cat "${OUTPUT}.sha256" | cut -d' ' -f1)"
}

# Main execution
main() {
    log "Starting SecureOS ISO generation"
    log "Source: $SOURCE"
    log "Output: $OUTPUT"
    
    # Create output directory if needed
    mkdir -p "$(dirname "$OUTPUT")"
    
    # Generate ISO
    copy_system_files
    setup_grub_bootloader
    create_live_boot
    generate_iso
    validate_iso
    
    log "✅ SecureOS ISO generation completed successfully"
}

# Execute main function
main "$@"