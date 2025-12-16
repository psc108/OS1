#!/bin/bash
# LFS Environment Setup Demo (Shows what would happen)
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

log_demo() {
    echo -e "${BLUE}[DEMO]${NC} $1"
}

log_info "LFS Environment Setup Demo - Showing what would happen..."

# Simulate disk scanning
log_check "Scanning for external disks with sufficient space..."

echo "Available external disks:"
echo "1) /dev/sda1 mounted at /mnt/secureos-sda1 (116GB available)"

echo
echo "Select location for LFS build environment:"
echo "1) Use system disk (requires 15GB+ free space)"
echo "2) Use external/removable disk"

# Simulate user selecting option 2
echo "User selects: 2"
echo

log_info "Selected external disk: /dev/sda1 (116GB available)"

# Show what would be created
LFS="/mnt/secureos-sda1/lfs"
log_info "LFS will be built at: $LFS"

log_demo "Would create directory structure:"
echo "  $LFS/"
echo "  ├── etc/"
echo "  ├── var/"
echo "  ├── usr/"
echo "  │   ├── bin/"
echo "  │   ├── lib/"
echo "  │   └── sbin/"
echo "  ├── sources/ (with sticky bit 1777)"
echo "  ├── tools/"
echo "  ├── bin -> usr/bin"
echo "  ├── lib -> usr/lib"
echo "  └── sbin -> usr/sbin"

log_demo "Would create /tools symlink -> $LFS/tools"

log_demo "Would create wrapper scripts:"
echo "  /usr/local/bin/gcc-wrapper"
echo "  /usr/local/bin/make-wrapper"

log_demo "Would create environment file ~/.lfs_env:"
echo "  export LFS=$LFS"
echo "  export LFS_TGT=x86_64-lfs-linux-gnu"
echo "  export PATH=/tools/bin:\$PATH"
echo "  export CONFIG_SITE=\$LFS/usr/share/config.site"
echo "  export MAKEFLAGS='-j$(nproc)'"

log_demo "Would validate setup:"
echo "  ✓ Directory structure"
echo "  ✓ Symbolic links"
echo "  ✓ Permissions"
echo "  ✓ Disk space (116GB available > 15GB required)"
echo "  ✓ Wrapper scripts"

log_info "=== DEMO SUMMARY ==="
log_info "The script would:"
log_info "1. Detect your external drive at /mnt/secureos-sda1 with 116GB"
log_info "2. Create LFS build environment at $LFS"
log_info "3. Set up proper directory structure following LFS book"
log_info "4. Create necessary symlinks and wrapper scripts"
log_info "5. Generate environment file for easy activation"
log_info "6. Validate the complete setup"

echo
log_info "To run the actual setup:"
log_info "  sudo ./setup_lfs_environment_interactive.sh"
log_info "  # Select option 2 for external disk"
log_info "  # Select option 1 for /dev/sda1"

echo
log_info "After setup, activate with:"
log_info "  source ~/.lfs_env"