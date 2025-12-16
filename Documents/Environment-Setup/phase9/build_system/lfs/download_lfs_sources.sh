#!/bin/bash
# Download and verify LFS sources (Phase 5 cryptographic verification pattern)
set -euo pipefail

echo "Downloading LFS sources with verification..."

LFS_VERSION="12.0"
LFS_BASE_URL="http://www.linuxfromscratch.org/lfs/downloads/stable"

# Download LFS book and package lists
wget -c "${LFS_BASE_URL}/LFS-BOOK-${LFS_VERSION}.pdf"
wget -c "${LFS_BASE_URL}/wget-list-sysv"
wget -c "${LFS_BASE_URL}/md5sums"

# Verify checksums (Phase 5 lesson - cryptographic verification required)
if ! md5sum -c md5sums; then
    echo "ERROR: LFS source verification failed"
    exit 1
fi

# Download all LFS packages with verification
export LFS=/mnt/lfs
wget --input-file=wget-list-sysv --continue --directory-prefix=$LFS/sources

# Verify all packages
cd $LFS/sources
if ! md5sum -c ../../../md5sums; then
    echo "ERROR: Package verification failed"
    exit 1
fi

echo "LFS sources downloaded and verified successfully"
