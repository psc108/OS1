#!/bin/bash
# Phase 8: Deployment Preparation Setup Script

set -euo pipefail

readonly PHASE8_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly LOG_FILE="$PHASE8_DIR/../common/logs/phase8_setup_$(date +%Y%m%d_%H%M%S).log"

log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE" >&2
}

install_docker_tools() {
    log_info "Installing Docker and container tools..."
    
    # Install Docker
    if ! command -v docker &> /dev/null; then
        dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
        dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
        systemctl enable --now docker
        usermod -aG docker "$SUDO_USER"
        log_success "Docker installed and configured"
    else
        log_info "Docker already installed"
    fi
    
    # Install container security tools
    dnf install -y podman buildah skopeo
    log_success "Container security tools installed"
}

install_iso_tools() {
    log_info "Installing ISO creation tools..."
    
    # Install ISO building tools
    dnf install -y genisoimage syslinux syslinux-efi64 xorriso
    dnf install -y dracut dracut-live dracut-network
    dnf install -y squashfs-tools
    
    # Install bootloader tools
    dnf install -y grub2-tools grub2-efi-x64 shim-x64
    
    log_success "ISO creation tools installed"
}

install_vmdk_tools() {
    log_info "Installing VMDK creation tools..."
    
    # Install QEMU for image conversion
    dnf install -y qemu-img qemu-kvm
    
    # Install VMware tools
    dnf install -y open-vm-tools
    
    log_success "VMDK creation tools installed"
}

install_build_dependencies() {
    log_info "Installing build system dependencies..."
    
    # Install build automation tools
    dnf install -y make cmake ninja-build
    dnf install -y python3-pip python3-virtualenv
    
    # Install security scanning tools
    dnf install -y clamav clamav-update
    pip3 install --user bandit safety
    
    # Install image optimization tools
    dnf install -y optipng jpegoptim
    
    log_success "Build dependencies installed"
}

setup_build_environment() {
    log_info "Setting up build environment..."
    
    # Create build directories
    mkdir -p "$PHASE8_DIR"/{build_output,temp_build,security_scans}
    
    # Set proper permissions
    chmod 755 "$PHASE8_DIR"/deployment/*/build_*.sh 2>/dev/null || true
    
    # Create build configuration
    cat > "$PHASE8_DIR/build_system/build_config.conf" << 'EOF'
# SecureOS Build Configuration
SECUREOS_VERSION=1.0.0
BUILD_DATE=$(date +%Y%m%d)
DOCKER_REGISTRY=secureos
ISO_LABEL=SecureOS-Live
VMDK_NAME=SecureOS-VM
SECURITY_BASELINE=CIS-Level2
EOF
    
    log_success "Build environment configured"
}

validate_prerequisites() {
    log_info "Validating Phase 8 prerequisites..."
    
    # Check previous phases
    local required_phases=(1 3 4 5 6 7)
    for phase in "${required_phases[@]}"; do
        if [ ! -d "$PHASE8_DIR/../phase$phase" ]; then
            log_error "Phase $phase not completed - required for Phase 8"
            return 1
        fi
    done
    
    # Check system resources
    local available_space=$(df "$PHASE8_DIR" | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt 10485760 ]; then  # 10GB in KB
        log_error "Insufficient disk space - need at least 10GB for image builds"
        return 1
    fi
    
    log_success "Prerequisites validated"
    return 0
}

create_deployment_scripts() {
    log_info "Creating deployment build scripts..."
    
    # Docker build script
    cat > "$PHASE8_DIR/deployment/docker/build_docker_image.sh" << 'EOF'
#!/bin/bash
# Docker Image Build Script
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../build_system/build_config.conf"

echo "Building SecureOS Docker image..."
docker build -t "$DOCKER_REGISTRY/secureos:$SECUREOS_VERSION" \
    -f "$SCRIPT_DIR/Dockerfile" \
    --build-arg BUILD_DATE="$BUILD_DATE" \
    --build-arg VERSION="$SECUREOS_VERSION" \
    "$SCRIPT_DIR"

echo "Docker image built successfully: $DOCKER_REGISTRY/secureos:$SECUREOS_VERSION"
EOF

    # ISO build script
    cat > "$PHASE8_DIR/deployment/iso/build_iso_image.sh" << 'EOF'
#!/bin/bash
# ISO Image Build Script
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../build_system/build_config.conf"

echo "Building SecureOS ISO image..."
# ISO build implementation will be added
echo "ISO image build script created - implementation pending"
EOF

    # VMDK build script
    cat > "$PHASE8_DIR/deployment/vmdk/build_vmdk_image.sh" << 'EOF'
#!/bin/bash
# VMDK Image Build Script
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../build_system/build_config.conf"

echo "Building SecureOS VMDK image..."
# VMDK build implementation will be added
echo "VMDK image build script created - implementation pending"
EOF

    chmod +x "$PHASE8_DIR"/deployment/*/build_*.sh
    log_success "Deployment build scripts created"
}

main() {
    log_info "Starting Phase 8: Deployment Preparation setup..."
    
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    if ! validate_prerequisites; then
        log_error "Prerequisites validation failed"
        exit 1
    fi
    
    install_docker_tools
    install_iso_tools
    install_vmdk_tools
    install_build_dependencies
    setup_build_environment
    create_deployment_scripts
    
    log_success "✅ Phase 8 setup completed successfully"
    log_info "Ready to build: Docker image, ISO image, VMDK image"
    log_info "Next: Run deployment build scripts in phase8/deployment/"
}

main "$@"