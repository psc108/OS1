#!/bin/bash
# SecureOS Build Starter Script
# Immediately starts OS building process in any deployment format
# Version: 1.0

set -euo pipefail

# Build options
BUILD_TYPE="${1:-lfs}"  # lfs, rocky, or both
SECURITY_LEVEL="${2:-production}"  # development or production

echo "Starting SecureOS build process..."
echo "Build Type: $BUILD_TYPE"
echo "Security Level: $SECURITY_LEVEL"

# Auto-prepare environment (always run)
if [[ -f /usr/local/bin/prepare_build_environment.sh ]]; then
    echo "Auto-configuring build environment..."
    /usr/local/bin/prepare_build_environment.sh
else
    echo "Setting up basic build environment..."
    export LFS=/mnt/lfs
    export LFS_TGT=x86_64-lfs-linux-gnu
    export PATH=/tools/bin:$PATH
    mkdir -p $LFS/{etc,var} $LFS/usr/{bin,lib,sbin} $LFS/sources $LFS/tools
    for i in bin lib sbin; do ln -sv usr/$i $LFS/$i 2>/dev/null || true; done
    chmod -v a+wt $LFS/sources 2>/dev/null || true
    ln -sv $LFS/tools / 2>/dev/null || true
fi

# Start appropriate build
case "$BUILD_TYPE" in
    lfs)
        echo "Starting Linux From Scratch build..."
        cd /opt/secureos/build_system/lfs
        ./setup_lfs_environment.sh
        ./download_lfs_sources.sh
        echo "✅ LFS environment ready for immediate development"
        echo "All LFS build tools and directories configured"
        ;;
    rocky)
        echo "Starting Rocky Linux build..."
        mkdir -p /opt/secureos/build_system/rocky
        cd /opt/secureos/build_system/rocky
        rpmdev-setuptree 2>/dev/null || true
        echo "✅ Rocky Linux environment ready for immediate development"
        echo "RPM build environment configured"
        ;;
    both)
        echo "Setting up both LFS and Rocky Linux environments..."
        $0 lfs "$SECURITY_LEVEL"
        $0 rocky "$SECURITY_LEVEL"
        echo "✅ Complete development environment ready"
        ;;
    *)
        echo "Unknown build type: $BUILD_TYPE"
        echo "Usage: $0 [lfs|rocky|both] [development|production]"
        exit 1
        ;;
esac

echo "SecureOS build environment is ready!"