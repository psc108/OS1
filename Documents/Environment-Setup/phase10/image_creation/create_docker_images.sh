#!/bin/bash
# Create SecureOS Docker Images
# Uses existing system packages for faster builds
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Parse command line arguments
SOURCE=""
TAG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --source=*)
            SOURCE="${1#*=}"
            shift
            ;;
        --tag=*)
            TAG="${1#*=}"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

[[ -z "$SOURCE" ]] && { echo "ERROR: Source is required (lfs|rocky)"; exit 1; }
[[ -z "$TAG" ]] && TAG="secureos/$SOURCE:latest"

log "Creating Docker image for $SOURCE target..."
log "Tag: $TAG"

# Create Dockerfile for LFS-based SecureOS
create_lfs_dockerfile() {
    log "Creating LFS-based Dockerfile..."
    
    cat > /tmp/Dockerfile.secureos-lfs << 'EOF'
FROM rockylinux:9

# Install LFS-equivalent development tools
RUN dnf groupinstall -y "Development Tools" && \
    dnf install -y gcc gcc-c++ binutils make autoconf automake libtool \
                   flex bison gawk patch wget curl git \
                   gdb valgrind clang \
                   openssl-devel ncurses-devel \
                   tar gzip bzip2 xz && \
    dnf clean all

# Create LFS-like directory structure
RUN mkdir -p /opt/lfs/{toolchain,sources,build_logs} && \
    mkdir -p /opt/secureos && \
    mkdir -p /tools && \
    ln -sf /usr/bin /tools/bin && \
    ln -sf /usr/lib /tools/lib && \
    ln -sf /usr/lib64 /tools/lib64

# Copy SecureOS components
COPY phase3 /opt/secureos/core_systems/
COPY phase4 /opt/secureos/system_services/
COPY phase5 /opt/secureos/user_space/

# Set LFS environment variables
ENV LFS=/opt/lfs \
    LFS_TGT=x86_64-lfs-linux-gnu \
    PATH=/tools/bin:/usr/bin:/bin:/usr/sbin:/sbin

# Create secureos user
RUN useradd -m -s /bin/bash secureos && \
    echo "secureos ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Set working directory and user
WORKDIR /home/secureos
USER secureos

# Create welcome message
RUN echo 'echo "🎉 SecureOS LFS Environment Ready!"' >> ~/.bashrc && \
    echo 'echo "✅ GCC: $(gcc --version | head -1)"' >> ~/.bashrc && \
    echo 'echo "✅ Make: $(make --version | head -1)"' >> ~/.bashrc && \
    echo 'echo "✅ SecureOS components: /opt/secureos/"' >> ~/.bashrc && \
    echo 'echo "Test: gcc -o test <(echo \"int main(){printf(\\\"LFS works!\\\\n\\\");return 0;}\") && ./test"' >> ~/.bashrc

CMD ["/bin/bash"]
EOF
    
    log "✅ LFS Dockerfile created"
}

# Build Docker image
build_docker_image() {
    log "Building Docker image..."
    
    # Create build context
    BUILD_CONTEXT="/tmp/secureos-docker-build"
    mkdir -p "$BUILD_CONTEXT"
    
    # Copy SecureOS components to build context
    if [[ -d "$BASE_DIR/phase3" ]]; then
        cp -r "$BASE_DIR/phase3" "$BUILD_CONTEXT/"
    else
        mkdir -p "$BUILD_CONTEXT/phase3"
        echo "# Phase 3 components placeholder" > "$BUILD_CONTEXT/phase3/README.md"
    fi
    
    if [[ -d "$BASE_DIR/phase4" ]]; then
        cp -r "$BASE_DIR/phase4" "$BUILD_CONTEXT/"
    else
        mkdir -p "$BUILD_CONTEXT/phase4"
        echo "# Phase 4 components placeholder" > "$BUILD_CONTEXT/phase4/README.md"
    fi
    
    if [[ -d "$BASE_DIR/phase5" ]]; then
        cp -r "$BASE_DIR/phase5" "$BUILD_CONTEXT/"
    else
        mkdir -p "$BUILD_CONTEXT/phase5"
        echo "# Phase 5 components placeholder" > "$BUILD_CONTEXT/phase5/README.md"
    fi
    
    # Copy Dockerfile to build context
    cp "/tmp/Dockerfile.secureos-lfs" "$BUILD_CONTEXT/Dockerfile"
    
    # Build image
    cd "$BUILD_CONTEXT"
    docker build -t "$TAG" . || {
        log "ERROR: Docker build failed"
        exit 1
    }
    
    # Cleanup
    rm -rf "$BUILD_CONTEXT"
    rm -f "/tmp/Dockerfile.secureos-lfs"
    
    log "✅ Docker image built successfully: $TAG"
}

# Test Docker image
test_docker_image() {
    log "Testing Docker image..."
    
    # Test basic functionality
    docker run --rm "$TAG" bash -c "gcc --version && make --version && ls /opt/secureos/" || {
        log "ERROR: Docker image test failed"
        exit 1
    }
    
    log "✅ Docker image test passed"
}

# Main execution
main() {
    log "Starting Docker image creation for $SOURCE"
    
    case "$SOURCE" in
        lfs)
            create_lfs_dockerfile
            build_docker_image
            test_docker_image
            ;;
        rocky)
            log "Rocky Linux Docker image creation not yet implemented"
            exit 1
            ;;
        *)
            log "ERROR: Invalid source: $SOURCE"
            exit 1
            ;;
    esac
    
    log "✅ Docker image creation completed successfully"
    log "Usage: docker run -it $TAG"
}

# Execute main function
main "$@"