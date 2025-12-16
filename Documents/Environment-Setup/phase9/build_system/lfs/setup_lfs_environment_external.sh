#!/bin/bash
# LFS Environment Setup (External Drive Version)
# Uses external drive with sufficient space
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    log_error "This script should NOT be run as root for security reasons"
    log_info "Run as regular user with sudo access"
    exit 1
fi

# Check sudo access
if ! sudo -n true 2>/dev/null; then
    log_error "This script requires sudo access"
    exit 1
fi

log_info "Setting up LFS build environment on external drive..."

# Use external drive with sufficient space
export LFS=/mnt/secureos-sda1/lfs
export LFS_TGT=x86_64-lfs-linux-gnu
export CONFIG_SITE=$LFS/usr/share/config.site

# Validate external drive is mounted and has space
if [[ ! -d "/mnt/secureos-sda1" ]]; then
    log_error "External drive not mounted at /mnt/secureos-sda1"
    exit 1
fi

AVAILABLE_SPACE=$(df /mnt/secureos-sda1 | awk 'NR==2 {print $4}')
REQUIRED_SPACE=$((15 * 1024 * 1024)) # 15GB in KB

if [[ $AVAILABLE_SPACE -lt $REQUIRED_SPACE ]]; then
    log_error "Insufficient disk space on external drive. Required: 15GB, Available: $((AVAILABLE_SPACE / 1024 / 1024))GB"
    exit 1
fi

log_info "Using external drive with $((AVAILABLE_SPACE / 1024 / 1024))GB available space"

# Create LFS directory structure with proper permissions
log_info "Creating LFS directory structure on external drive..."

# Create main LFS directory
if [[ ! -d "$LFS" ]]; then
    mkdir -pv "$LFS"
    log_info "Created $LFS directory"
else
    log_warn "$LFS directory already exists"
fi

# Set ownership to current user (external drive should be writable)
chown -v "$USER:$USER" "$LFS" 2>/dev/null || log_warn "Could not change ownership (may not be needed)"
log_info "Set ownership of $LFS to $USER"

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

# Create wrapper scripts directory
WRAPPER_DIR="/usr/local/bin"
log_info "Setting up compiler wrappers..."

# Create GCC wrapper script
sudo tee "$WRAPPER_DIR/gcc-wrapper" > /dev/null << 'EOF'
#!/bin/bash
# GCC wrapper for LFS build
exec /usr/bin/gcc "$@"
EOF

sudo chmod +x "$WRAPPER_DIR/gcc-wrapper"
log_info "Created GCC wrapper"

# Create Make wrapper script
sudo tee "$WRAPPER_DIR/make-wrapper" > /dev/null << 'EOF'
#!/bin/bash
# Make wrapper for LFS build
exec /usr/bin/make "$@"
EOF

sudo chmod +x "$WRAPPER_DIR/make-wrapper"
log_info "Created Make wrapper"

# Set up environment file
log_info "Creating LFS environment file..."
cat > "$HOME/.lfs_env" << EOF
# LFS Environment Variables (External Drive)
export LFS=$LFS
export LFS_TGT=$LFS_TGT
export PATH=/tools/bin:\$PATH
export CONFIG_SITE=\$LFS/usr/share/config.site
export MAKEFLAGS='-j$(nproc)'
EOF

log_info "LFS environment file created at $HOME/.lfs_env"

# Validate the setup
log_info "Validating LFS environment setup..."

# Check directory structure
VALIDATION_PASSED=true

for dir in "$LFS" "$LFS/etc" "$LFS/var" "$LFS/usr/bin" "$LFS/usr/lib" "$LFS/usr/sbin" "$LFS/sources" "$LFS/tools"; do
    if [[ ! -d "$dir" ]]; then
        log_error "Directory $dir does not exist"
        VALIDATION_PASSED=false
    fi
done

# Check symbolic links
for link in "$LFS/bin" "$LFS/lib" "$LFS/sbin"; do
    if [[ ! -L "$link" ]]; then
        log_error "Symbolic link $link does not exist"
        VALIDATION_PASSED=false
    fi
done

# Check tools symlink
if [[ ! -L "/tools" ]]; then
    log_error "/tools symlink does not exist"
    VALIDATION_PASSED=false
fi

# Check wrapper scripts
for wrapper in "$WRAPPER_DIR/gcc-wrapper" "$WRAPPER_DIR/make-wrapper"; do
    if [[ ! -x "$wrapper" ]]; then
        log_error "Wrapper script $wrapper is not executable"
        VALIDATION_PASSED=false
    fi
done

# Check permissions
if [[ ! -w "$LFS/sources" ]]; then
    log_error "$LFS/sources is not writable"
    VALIDATION_PASSED=false
fi

if [[ $VALIDATION_PASSED == true ]]; then
    log_info "LFS environment setup completed successfully!"
    log_info "To activate the environment, run: source ~/.lfs_env"
    log_info "Directory structure:"
    tree -L 3 "$LFS" 2>/dev/null || ls -la "$LFS"
else
    log_error "LFS environment setup validation failed"
    exit 1
fi

# Create usage instructions
cat > "$LFS/README_LFS_SETUP.md" << 'EOF'
# LFS Environment Setup (External Drive)

## Environment Activation
```bash
source ~/.lfs_env
```

## Directory Structure
- `/mnt/secureos-sda1/lfs` - Main LFS build directory (on external drive)
- `/mnt/secureos-sda1/lfs/sources` - Source packages
- `/mnt/secureos-sda1/lfs/tools` - Cross-compilation tools
- `/tools` - Symlink to `/mnt/secureos-sda1/lfs/tools`

## Environment Variables
- `LFS=/mnt/secureos-sda1/lfs`
- `LFS_TGT=x86_64-lfs-linux-gnu`
- `PATH=/tools/bin:$PATH`
- `CONFIG_SITE=$LFS/usr/share/config.site`

## Next Steps
1. Download LFS source packages
2. Build cross-compilation toolchain
3. Build temporary system
4. Build final LFS system

## Validation
Run the validation script to verify setup:
```bash
./validate_lfs_environment_external.sh
```
EOF

log_info "Setup documentation created at $LFS/README_LFS_SETUP.md"
log_info "External drive location: /mnt/secureos-sda1/lfs"
log_info "Available space: $((AVAILABLE_SPACE / 1024 / 1024))GB"