#!/bin/bash
# LFS Environment Setup (Fixed Version)
# Addresses permission issues and follows LFS book requirements
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

log_info "Setting up LFS build environment (Fixed Version)..."

# LFS environment variables (following LFS book exactly)
export LFS=/mnt/lfs
export LFS_TGT=x86_64-lfs-linux-gnu
export CONFIG_SITE=$LFS/usr/share/config.site

# Validate disk space (LFS requires at least 15GB)
AVAILABLE_SPACE=$(df / | awk 'NR==2 {print $4}')
REQUIRED_SPACE=$((15 * 1024 * 1024)) # 15GB in KB

if [[ $AVAILABLE_SPACE -lt $REQUIRED_SPACE ]]; then
    log_error "Insufficient disk space. Required: 15GB, Available: $((AVAILABLE_SPACE / 1024 / 1024))GB"
    exit 1
fi

# Create LFS directory structure with proper permissions
log_info "Creating LFS directory structure..."

# Create main LFS directory
if [[ ! -d "$LFS" ]]; then
    sudo mkdir -pv "$LFS"
    log_info "Created $LFS directory"
else
    log_warn "$LFS directory already exists"
fi

# Set ownership to current user
sudo chown -v "$USER:$USER" "$LFS"
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
# LFS Environment Variables
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
# LFS Environment Setup

## Environment Activation
```bash
source ~/.lfs_env
```

## Directory Structure
- `/mnt/lfs` - Main LFS build directory
- `/mnt/lfs/sources` - Source packages
- `/mnt/lfs/tools` - Cross-compilation tools
- `/tools` - Symlink to `/mnt/lfs/tools`

## Environment Variables
- `LFS=/mnt/lfs`
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
./validate_lfs_environment.sh
```
EOF

log_info "Setup documentation created at $LFS/README_LFS_SETUP.md"