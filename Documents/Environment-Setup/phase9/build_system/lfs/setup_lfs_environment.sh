#!/bin/bash
# LFS Environment Setup (Following LFS Book Exactly)
set -euo pipefail

echo "Setting up LFS build environment..."

# LFS environment variables (following LFS book exactly)
export LFS=/mnt/lfs
export LFS_TGT=x86_64-lfs-linux-gnu
export PATH=/tools/bin:$PATH
export CONFIG_SITE=$LFS/usr/share/config.site

# Create LFS directory structure
sudo mkdir -pv $LFS
sudo chown -v $USER $LFS
mkdir -pv $LFS/{etc,var} $LFS/usr/{bin,lib,sbin}
for i in bin lib sbin; do
  ln -sv usr/$i $LFS/$i
done

# Setup sources directory
mkdir -pv $LFS/sources
chmod -v a+wt $LFS/sources

# Setup tools directory for cross-compilation
mkdir -pv $LFS/tools
ln -sv $LFS/tools /

echo "LFS environment setup completed"
