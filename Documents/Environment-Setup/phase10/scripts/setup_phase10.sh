#!/bin/bash
# Phase 10 Setup Script
# Prepares automated OS build system using all prior phases
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE10_DIR="$(dirname "$SCRIPT_DIR")"
BASE_DIR="$(dirname "$PHASE10_DIR")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "Setting up Phase 10: Automated OS Build System"

# Validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites from prior phases..."
    
    # Check Phase 9 bootstrap environment
    if [[ ! -f "$BASE_DIR/phase9/build_system/lfs/setup_lfs_environment_interactive.sh" ]]; then
        echo "ERROR: Phase 9 LFS environment not found"
        echo "Please complete Phase 9 setup first:"
        echo "  cd $BASE_DIR/phase9/build_system/lfs/"
        echo "  ./setup_lfs_environment_interactive.sh"
        exit 1
    fi
    
    # Check Phase 3-6 security components
    for phase in 3 4 5 6; do
        if [[ ! -d "$BASE_DIR/phase$phase" ]]; then
            echo "ERROR: Phase $phase not found"
            echo "Please complete Phase $phase first"
            exit 1
        fi
    done
    
    # Check Phase 7 testing tools
    if [[ ! -d "$BASE_DIR/phase7/testing_tools" ]]; then
        echo "ERROR: Phase 7 testing tools not found"
        echo "Please complete Phase 7 first"
        exit 1
    fi
    
    log "✅ All prerequisites validated"
}

# Setup LFS environment
setup_lfs_environment() {
    log "Setting up LFS environment for automated builds..."
    
    if [[ ! -f ~/.lfs_env ]]; then
        log "LFS environment not configured, setting up..."
        cd "$BASE_DIR/phase9/build_system/lfs/"
        ./setup_lfs_environment_interactive.sh --non-interactive --auto-detect
    fi
    
    # Source LFS environment
    source ~/.lfs_env
    log "✅ LFS environment ready: $LFS"
}

# Install build dependencies
install_dependencies() {
    log "Installing build dependencies..."
    
    # Essential build tools
    local packages=(
        "gcc" "gcc-c++" "make" "binutils" "tar" "gzip" "bzip2" "xz"
        "wget" "curl" "git" "patch" "diffutils" "findutils" "gawk"
        "qemu-img" "parted" "dosfstools" "e2fsprogs"
    )
    
    # Image generation tools
    local image_packages=(
        "xorriso" "syslinux" "grub2-tools" "grub2-efi-x64"
    )
    
    # Check and install missing packages
    local missing_packages=()
    
    for package in "${packages[@]}" "${image_packages[@]}"; do
        if ! rpm -q "$package" >/dev/null 2>&1; then
            missing_packages+=("$package")
        fi
    done
    
    if [[ ${#missing_packages[@]} -gt 0 ]]; then
        log "Installing missing packages: ${missing_packages[*]}"
        sudo dnf install -y "${missing_packages[@]}" || {
            log "WARNING: Some packages could not be installed"
            log "Build system may have limited functionality"
        }
    else
        log "✅ All required packages already installed"
    fi
}

# Validate Phase 10 setup
validate_setup() {
    log "Validating Phase 10 setup..."
    
    # Run validation script
    "$SCRIPT_DIR/validate_build_system.sh" --comprehensive || {
        echo "ERROR: Phase 10 validation failed"
        exit 1
    }
    
    log "✅ Phase 10 setup validation passed"
}

# Create example build commands
create_examples() {
    log "Creating example build commands..."
    
    cat > "$PHASE10_DIR/EXAMPLES.md" << 'EOF'
# Phase 10 Build Examples

## Quick Start Commands

### Build LFS-based SecureOS ISO
```bash
cd Documents/Environment-Setup/phase10/scripts/
sudo ./build_secureos.sh --target=lfs --format=iso --output=/tmp/SecureOS-LFS.iso
```

### Build Rocky-based SecureOS VMDK
```bash
sudo ./build_secureos.sh --target=rocky --format=vmdk --output=/tmp/SecureOS-Rocky.vmdk
```

### Build All Formats
```bash
sudo ./build_secureos.sh --target=both --format=all --output-dir=/tmp/SecureOS-Complete/
```

## Validation Commands

### Comprehensive Validation
```bash
./validate_build_system.sh --comprehensive --all-formats
```

### Security Audit
```bash
./audit_build_security.sh --zero-tolerance --detailed-report
```

## Expected Build Times
- LFS ISO: 6-8 hours (depending on hardware)
- Rocky VMDK: 4-6 hours (depending on hardware)
- All formats: 8-12 hours (depending on hardware)

## Expected Output Sizes
- LFS ISO: ~2GB
- LFS VMDK: ~6GB
- Rocky ISO: ~3GB
- Rocky VMDK: ~8GB
- Docker images: <500MB compressed

## Troubleshooting
- Ensure Phase 9 LFS environment is configured: `source ~/.lfs_env`
- Check disk space: Need 20GB+ free space for builds
- Verify all prior phases completed: Run validation script
EOF
    
    log "✅ Examples created: $PHASE10_DIR/EXAMPLES.md"
}

# Main setup function
main() {
    log "Starting Phase 10 setup..."
    
    validate_prerequisites
    setup_lfs_environment
    install_dependencies
    validate_setup
    create_examples
    
    log "✅ Phase 10 setup completed successfully!"
    log ""
    log "Phase 10: Automated OS Build System is ready!"
    log ""
    log "Quick start:"
    log "  cd $SCRIPT_DIR"
    log "  sudo ./build_secureos.sh --target=lfs --format=iso --output=/tmp/SecureOS-LFS.iso"
    log ""
    log "For more examples, see: $PHASE10_DIR/EXAMPLES.md"
    log "For validation: ./validate_build_system.sh --comprehensive"
}

# Execute main function
main "$@"