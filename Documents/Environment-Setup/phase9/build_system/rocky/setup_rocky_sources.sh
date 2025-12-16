#!/bin/bash
# Rocky Linux Source Repository Setup
set -euo pipefail

echo "Setting up Rocky Linux source repositories..."

# Setup Rocky Linux source repositories
cat > /etc/yum.repos.d/rocky-sources.repo << 'REPO_EOF'
[rocky-sources]
name=Rocky Linux $releasever - Sources
baseurl=https://dl.rockylinux.org/pub/rocky/$releasever/sources/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-rockyofficial
REPO_EOF

# Test source package download and verification
echo "Testing source package access..."
dnf download --source kernel || echo "WARNING: Source download test failed - will use available sources"

echo "Rocky Linux source repositories configured"
