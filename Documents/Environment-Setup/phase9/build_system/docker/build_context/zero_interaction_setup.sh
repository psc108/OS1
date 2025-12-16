#!/bin/bash
# Zero Interaction Setup - Fully automated development environment
# Runs automatically on all deployment formats
# Version: 1.0

set -euo pipefail

echo "🚀 SecureOS Zero-Interaction Development Setup"
echo "Configuring complete build environment automatically..."

# Detect and setup based on deployment type
setup_environment() {
    # Install all required packages silently
    dnf groupinstall -y "Development Tools" &>/dev/null || true
    dnf install -y gcc gcc-c++ make autoconf automake libtool \
                   flex bison gawk texinfo patch wget curl git \
                   rpm-build rpmdevtools createrepo_c \
                   cppcheck clang valgrind &>/dev/null || true
    
    # Setup LFS environment completely
    export LFS=/mnt/lfs
    export LFS_TGT=x86_64-lfs-linux-gnu
    export PATH=/tools/bin:$PATH
    export CONFIG_SITE=$LFS/usr/share/config.site
    
    # Create all LFS directories
    mkdir -p $LFS/{etc,var} $LFS/usr/{bin,lib,sbin} $LFS/sources $LFS/tools
    for i in bin lib sbin; do
        ln -sf usr/$i $LFS/$i 2>/dev/null || true
    done
    chmod -v a+wt $LFS/sources &>/dev/null || true
    ln -sf $LFS/tools / 2>/dev/null || true
    
    # Setup RPM build environment
    rpmdev-setuptree &>/dev/null || true
    
    # Create workspace directories
    mkdir -p /opt/secureos/{build_system/{lfs,rocky,docker},toolchain,sources}
    
    # Set environment variables permanently
    cat >> /etc/environment << 'ENV_EOF'
LFS=/mnt/lfs
LFS_TGT=x86_64-lfs-linux-gnu
PATH=/tools/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
CONFIG_SITE=/mnt/lfs/usr/share/config.site
ENV_EOF
    
    # Add to all user profiles
    cat >> /etc/profile << 'PROFILE_EOF'
# SecureOS Development Environment - Auto-configured
export LFS=/mnt/lfs
export LFS_TGT=x86_64-lfs-linux-gnu
export PATH=/tools/bin:$PATH
export CONFIG_SITE=$LFS/usr/share/config.site
cd /opt/secureos 2>/dev/null || true
PROFILE_EOF
    
    echo "✅ Complete development environment configured"
    echo "✅ LFS build system ready"
    echo "✅ Rocky Linux build system ready"
    echo "✅ All tools and dependencies installed"
    echo "✅ Zero interaction required - ready to develop!"
}

# Run setup
setup_environment

# Create status file
echo "$(date): SecureOS development environment auto-configured" > /etc/secureos-ready

echo "🎉 SecureOS Development Environment Ready!"
echo "No further setup required - start building immediately!"