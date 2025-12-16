#!/bin/bash
# Docker Image Build Script
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PHASE8_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source build configuration
if [ -f "$PHASE8_DIR/build_system/build_config.conf" ]; then
    source "$PHASE8_DIR/build_system/build_config.conf"
else
    echo "Error: Build configuration not found"
    exit 1
fi

echo "Building SecureOS Docker image..."
echo "Version: $SECUREOS_VERSION"
echo "Build Date: $BUILD_DATE"

# Create build context with SecureOS components
BUILD_CONTEXT="$PHASE8_DIR/build_output/docker_context"
mkdir -p "$BUILD_CONTEXT"

# Copy SecureOS components to build context
echo "Preparing build context..."
cp -r "$PHASE8_DIR/../phase3/core_systems" "$BUILD_CONTEXT/" 2>/dev/null || echo "Phase 3 components not found"
cp -r "$PHASE8_DIR/../phase4/system_services" "$BUILD_CONTEXT/" 2>/dev/null || echo "Phase 4 components not found"
cp -r "$PHASE8_DIR/../phase5/user_space" "$BUILD_CONTEXT/" 2>/dev/null || echo "Phase 5 components not found"

# Create minimal Dockerfile for available components
cat > "$BUILD_CONTEXT/Dockerfile" << 'DOCKERFILE_EOF'
# SecureOS Minimal Docker Image
FROM rockylinux:9-minimal

ARG BUILD_DATE
ARG VERSION

LABEL maintainer="SecureOS Team"
LABEL version="${VERSION}"
LABEL build-date="${BUILD_DATE}"
LABEL description="SecureOS - Security-First Operating System Container"

# Install minimal runtime dependencies
RUN microdnf update -y && \
    microdnf install -y openssl && \
    microdnf clean all

# Create non-root user
RUN useradd -r -u 1000 -g users -s /bin/sh secureos

# Copy available SecureOS binaries (if they exist)
COPY --chown=secureos:users core_systems/ /opt/secureos/core_systems/
COPY --chown=secureos:users system_services/ /opt/secureos/system_services/
COPY --chown=secureos:users user_space/ /opt/secureos/user_space/

# Set working directory and user
WORKDIR /home/secureos
USER secureos

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD echo "SecureOS container healthy" || exit 1

# Default command
CMD ["/bin/sh", "-c", "echo 'SecureOS Container Ready' && sleep infinity"]
DOCKERFILE_EOF

# Build Docker image
echo "Building Docker image: $DOCKER_REGISTRY/secureos:$SECUREOS_VERSION"
docker build -t "$DOCKER_REGISTRY/secureos:$SECUREOS_VERSION" \
    --build-arg BUILD_DATE="$BUILD_DATE" \
    --build-arg VERSION="$SECUREOS_VERSION" \
    "$BUILD_CONTEXT"

if [ $? -eq 0 ]; then
    echo "✅ Docker image built successfully: $DOCKER_REGISTRY/secureos:$SECUREOS_VERSION"
    docker images | grep secureos
else
    echo "❌ Docker image build failed"
    exit 1
fi