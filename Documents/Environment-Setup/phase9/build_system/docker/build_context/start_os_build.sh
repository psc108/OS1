#!/bin/bash
set -euo pipefail

BUILD_TYPE="${1:-lfs}"
echo "Starting SecureOS build: $BUILD_TYPE"

export LFS=/mnt/lfs
export LFS_TGT=x86_64-lfs-linux-gnu
export PATH=/tools/bin:$PATH

case "$BUILD_TYPE" in
    lfs)
        echo "LFS environment ready"
        ;;
    rocky)
        if command -v rpmdev-setuptree >/dev/null 2>&1; then
            rpmdev-setuptree
        else
            mkdir -p ~/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
        fi
        echo "Rocky environment ready"
        ;;
    *)
        echo "Usage: $0 [lfs|rocky]"
        exit 1
        ;;
esac