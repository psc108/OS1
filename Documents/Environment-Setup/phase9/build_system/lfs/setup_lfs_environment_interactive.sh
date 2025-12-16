#!/bin/bash
# LFS Environment Setup (Interactive Version)
# Allows user to select destination with sufficient space
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_check() {
    echo -e "${BLUE}[CHECK]${NC} $1"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    log_error "This script should NOT be run as root for security reasons"
    log_info "Run as regular user with sudo access"
    exit 1
fi

# Check sudo access
if ! sudo -v 2>/dev/null; then
    log_error "This script requires sudo access"
    exit 1
fi

# Storage configuration (will be set by user selection)
LFS_BASE_PATH=""
USE_EXTERNAL_DISK=false

# Disk selection functions
select_lfs_location() {
    log_info "LFS build location selection..."
    
    echo "Select location for LFS build environment:"
    echo "1) Use system disk (requires 15GB+ free space)"
    echo "2) Use external/removable disk"
    
    while true; do
        read -r -p "Enter choice [1-2]: " choice
        case $choice in
            1)
                LFS_BASE_PATH="/mnt/lfs"
                USE_EXTERNAL_DISK=false
                break
                ;;
            2)
                select_external_disk
                break
                ;;
            *)
                echo "Invalid choice. Please enter 1 or 2."
                ;;
        esac
    done
}

select_external_disk() {
    log_info "Scanning for external disks with sufficient space..."
    
    local suitable_disks=()
    
    # Check all partitions, including unmounted ones
    while IFS= read -r line; do
        local device size mount
        read -r device _ size mount <<< "$line"
        
        # Skip system devices (nvme, md, dm, loop)
        local base_device
        base_device=${device//[0-9]/}
        [[ "$base_device" =~ ^(nvme|md|dm-|loop) ]] && continue
        
        # Skip system mount points
        [[ "$mount" =~ ^(/|/boot|/home|/var|/usr)$ ]] && continue
        
        # Convert size to GB (handle decimal values)
        local size_gb=0
        if [[ "$size" =~ ([0-9]+)\.?[0-9]*T ]]; then
            # Extract integer part for TB
            local tb_int
            tb_int=${size%%.*}
            size_gb=$((tb_int * 1024))
        elif [[ "$size" =~ ([0-9]+)\.?[0-9]*G ]]; then
            # Extract integer part for GB
            local gb_int
            gb_int=${size%%.*}
            size_gb=$gb_int
        fi
        
        # Check if device has enough space (15GB minimum)
        if [[ $size_gb -ge 15 ]]; then
            if [[ -n "$mount" ]]; then
                # Mounted - check actual free space
                local available_gb
                available_gb=$(df "$mount" 2>/dev/null | awk 'NR==2{print int($4/1024/1024)}' || echo "0")
                if [[ $available_gb -ge 15 ]]; then
                    suitable_disks+=("$device:$mount:${available_gb}GB:mounted")
                fi
            else
                # Unmounted - use total size as estimate
                suitable_disks+=("$device::${size_gb}GB:unmounted")
            fi
        fi
    done < <(lsblk -rno NAME,TYPE,SIZE,MOUNTPOINT | grep "part")
    
    if [[ ${#suitable_disks[@]} -eq 0 ]]; then
        log_error "No suitable external disks found (need 15GB+ space)"
        echo "Available devices:"
        lsblk -o NAME,TYPE,SIZE,MOUNTPOINT | grep -E "(disk|part)"
        exit 1
    fi
    
    # Show available disks
    echo "Available external disks:"
    for i in "${!suitable_disks[@]}"; do
        IFS=':' read -r device mount size status <<< "${suitable_disks[$i]}"
        if [[ "$status" == "mounted" ]]; then
            echo "$((i+1))) /dev/$device mounted at $mount ($size available)"
        else
            echo "$((i+1))) /dev/$device unmounted ($size total)"
        fi
    done
    
    # Select disk
    while true; do
        read -r -p "Select external disk [1-${#suitable_disks[@]}]: " disk_choice
        if [[ "$disk_choice" =~ ^[0-9]+$ ]] && 
           [[ $disk_choice -ge 1 ]] && 
           [[ $disk_choice -le ${#suitable_disks[@]} ]]; then
            
            IFS=':' read -r selected_device selected_mount selected_size selected_status <<< "${suitable_disks[$((disk_choice-1))]}"
            
            if [[ "$selected_status" == "unmounted" ]]; then
                # Mount the device
                local mount_point="/mnt/lfs-${selected_device}"
                sudo mkdir -p "$mount_point"
                if sudo mount "/dev/$selected_device" "$mount_point"; then
                    LFS_BASE_PATH="$mount_point/lfs"
                    USE_EXTERNAL_DISK=true
                    sudo mkdir -p "$LFS_BASE_PATH"
                    sudo chown "$USER:$USER" "$LFS_BASE_PATH"
                    log_info "Mounted and selected: /dev/$selected_device at $mount_point ($selected_size)"
                else
                    log_error "Failed to mount /dev/$selected_device"
                    exit 1
                fi
            else
                LFS_BASE_PATH="$selected_mount/lfs"
                USE_EXTERNAL_DISK=true
                mkdir -p "$LFS_BASE_PATH"
                log_info "Selected external disk: /dev/$selected_device ($selected_size available)"
            fi
            break
        else
            echo "Invalid choice. Please enter a number between 1 and ${#suitable_disks[@]}."
        fi
    done
}

# Validate disk space
validate_disk_space() {
    log_check "Validating disk space..."
    
    local available_space
    if [[ "$USE_EXTERNAL_DISK" == "false" ]]; then
        # Check root filesystem space
        available_space=$(df / | awk 'NR==2 {print $4}')
    else
        # Check external disk space
        available_space=$(df "$LFS_BASE_PATH" | awk 'NR==2 {print $4}')
    fi
    
    local required_space=$((15 * 1024 * 1024)) # 15GB in KB
    
    if [[ $available_space -lt $required_space ]]; then
        log_error "Insufficient disk space. Required: 15GB, Available: $((available_space / 1024 / 1024))GB"
        exit 1
    fi
    
    log_info "Sufficient disk space available: $((available_space / 1024 / 1024))GB"
}

# Main LFS setup function
setup_lfs_environment() {
    log_info "Setting up LFS build environment..."
    
    # LFS environment variables
    export LFS="$LFS_BASE_PATH"
    export LFS_TGT=x86_64-lfs-linux-gnu
    export CONFIG_SITE="$LFS/usr/share/config.site"
    
    log_info "LFS will be built at: $LFS"
    
    # Create LFS directory structure with proper permissions
    log_info "Creating LFS directory structure..."
    
    # Create main LFS directory
    if [[ ! -d "$LFS" ]]; then
        if [[ "$USE_EXTERNAL_DISK" == "false" ]]; then
            sudo mkdir -pv "$LFS"
            sudo chown -v "$USER:$USER" "$LFS"
        else
            mkdir -pv "$LFS"
        fi
        log_info "Created $LFS directory"
    else
        log_warn "$LFS directory already exists"
    fi
    
    # Create subdirectories
    mkdir -pv "$LFS"/{etc,var,usr/{bin,lib,sbin}}
    log_info "Created LFS subdirectories"
    
    # Create symbolic links for FHS compliance
    for i in bin lib sbin; do
        if [[ ! -L "$LFS/$i" ]]; then
            ln -sv "usr/$i" "$LFS/$i"
            log_info "Created symbolic link: $LFS/$i -> usr/$i"
        else
            log_warn "Symbolic link $LFS/$i already exists"
        fi
    done
    
    # Setup sources directory with proper permissions
    log_info "Setting up sources directory..."
    mkdir -pv "$LFS/sources"
    chmod -v a+wt "$LFS/sources"
    log_info "Sources directory created with sticky bit"
    
    # Setup tools directory for cross-compilation
    log_info "Setting up tools directory..."
    mkdir -pv "$LFS/tools"
    
    # Create tools symlink in root (requires sudo)
    if [[ ! -L "/tools" ]]; then
        sudo ln -sv "$LFS/tools" /
        log_info "Created /tools symlink"
    else
        log_warn "/tools symlink already exists"
        # Update symlink to point to new location
        sudo rm -f /tools
        sudo ln -sv "$LFS/tools" /
        log_info "Updated /tools symlink to new location"
    fi
    
    # Create wrapper scripts in LFS tools directory (no sudo needed)
    local wrapper_dir="$LFS/tools/bin"
    mkdir -p "$wrapper_dir"
    log_info "Setting up compiler wrappers in LFS tools..."
    
    # Create GCC wrapper script
    cat > "$wrapper_dir/gcc" << 'EOF'
#!/bin/bash
# GCC wrapper for LFS build
exec /usr/bin/gcc "$@"
EOF
    chmod +x "$wrapper_dir/gcc"
    log_info "Created GCC wrapper in LFS tools"
    
    # Create Make wrapper script
    cat > "$wrapper_dir/make" << 'EOF'
#!/bin/bash
# Make wrapper for LFS build
exec /usr/bin/make "$@"
EOF
    chmod +x "$wrapper_dir/make"
    log_info "Created Make wrapper in LFS tools"
    
    # Set up environment file
    log_info "Creating LFS environment file..."
    cat > "$HOME/.lfs_env" << EOF
# LFS Environment Variables
export LFS=$LFS
export LFS_TGT=$LFS_TGT
export PATH=/tools/bin:\$PATH
export CONFIG_SITE=\$LFS/usr/share/config.site
export MAKEFLAGS='-j$(nproc)'
EOF
    
    log_info "LFS environment file created at $HOME/.lfs_env"
}

# Validate the setup
validate_lfs_setup() {
    log_info "Validating LFS environment setup..."
    
    local validation_passed=true
    
    # Check directory structure
    local required_dirs=("$LFS" "$LFS/etc" "$LFS/var" "$LFS/usr/bin" "$LFS/usr/lib" "$LFS/usr/sbin" "$LFS/sources" "$LFS/tools")
    
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_error "Directory $dir does not exist"
            validation_passed=false
        fi
    done
    
    # Check symbolic links
    local required_links=("$LFS/bin" "$LFS/lib" "$LFS/sbin")
    
    for link in "${required_links[@]}"; do
        if [[ ! -L "$link" ]]; then
            log_error "Symbolic link $link does not exist"
            validation_passed=false
        fi
    done
    
    # Check tools symlink
    if [[ ! -L "/tools" ]]; then
        log_error "/tools symlink does not exist"
        validation_passed=false
    fi
    
    # Check wrapper scripts in LFS tools
    local wrapper_scripts=("$LFS/tools/bin/gcc" "$LFS/tools/bin/make")
    
    for wrapper in "${wrapper_scripts[@]}"; do
        if [[ -x "$wrapper" ]]; then
            log_info "✓ LFS wrapper script executable: $wrapper"
        else
            log_error "✗ LFS wrapper script not executable: $wrapper"
            validation_passed=false
        fi
    done
    
    # Check permissions
    if [[ ! -w "$LFS/sources" ]]; then
        log_error "$LFS/sources is not writable"
        validation_passed=false
    fi
    
    if [[ $validation_passed == true ]]; then
        log_info "✓ LFS environment setup validation PASSED"
        return 0
    else
        log_error "✗ LFS environment setup validation FAILED"
        return 1
    fi
}

# Create documentation
create_documentation() {
    log_info "Creating setup documentation..."
    
    cat > "$LFS/README_LFS_SETUP.md" << EOF
# LFS Environment Setup

## Location
- LFS Directory: $LFS
- External Disk: $USE_EXTERNAL_DISK

## Environment Activation
\`\`\`bash
source ~/.lfs_env
\`\`\`

## Directory Structure
- \`$LFS\` - Main LFS build directory
- \`$LFS/sources\` - Source packages
- \`$LFS/tools\` - Cross-compilation tools
- \`/tools\` - Symlink to \`$LFS/tools\`

## Environment Variables
- \`LFS=$LFS\`
- \`LFS_TGT=x86_64-lfs-linux-gnu\`
- \`PATH=/tools/bin:\$PATH\`
- \`CONFIG_SITE=\$LFS/usr/share/config.site\`

## Next Steps
1. Download LFS source packages: \`./download_lfs_sources.sh\`
2. Build cross-compilation toolchain
3. Build temporary system
4. Build final LFS system

## Validation
Run the validation script to verify setup:
\`\`\`bash
./validate_lfs_environment_interactive.sh
\`\`\`
EOF
    
    log_info "Setup documentation created at $LFS/README_LFS_SETUP.md"
}

# Main execution function
main() {
    log_info "Starting LFS environment setup (Interactive Version)..."
    
    # Select LFS location
    select_lfs_location
    
    # Validate disk space
    validate_disk_space
    
    # Setup LFS environment
    setup_lfs_environment
    
    # Validate setup
    if validate_lfs_setup; then
        # Create documentation
        create_documentation
        
        log_info "=== LFS ENVIRONMENT SETUP COMPLETED ==="
        log_info "LFS Directory: $LFS"
        log_info "External Disk: $USE_EXTERNAL_DISK"
        log_info "Available Space: $(df "$LFS" | awk 'NR==2{print int($4/1024/1024)}')GB"
        log_info ""
        log_info "To activate the environment:"
        log_info "  source ~/.lfs_env"
        log_info ""
        log_info "To validate the setup:"
        log_info "  ./validate_lfs_environment_interactive.sh"
        log_info ""
        log_info "Documentation: $LFS/README_LFS_SETUP.md"
    else
        log_error "LFS environment setup failed validation"
        exit 1
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi