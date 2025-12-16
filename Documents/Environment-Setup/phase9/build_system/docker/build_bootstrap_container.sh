#!/bin/bash
set -euo pipefail

echo "Building SecureOS Bootstrap Development Container..."

# Create build context with security components
mkdir -p build_context
cp -r ../../../phase3 build_context/
cp -r ../../../phase4 build_context/
cp -r ../../../phase5 build_context/
cp ../../scripts/prepare_build_environment.sh build_context/
cp ../../scripts/start_os_build.sh build_context/
cp ../../scripts/zero_interaction_setup.sh build_context/

# Build the container
docker build -f Dockerfile.bootstrap -t secureos/bootstrap-dev:1.0.0 . || {
    echo "Build failed, checking if base image exists..."
    if ! docker images | grep -q "secureos/secureos:1.0.0"; then
        echo "Base image not found, building from Phase 8..."
        cd ../../../phase8/deployment/docker/
        docker build -t secureos/secureos:1.0.0 . || exit 1
        cd -
        docker build -f Dockerfile.bootstrap -t secureos/bootstrap-dev:1.0.0 .
    else
        exit 1
    fi
}

# Clean up build context
rm -rf build_context

echo "Bootstrap container built successfully"
