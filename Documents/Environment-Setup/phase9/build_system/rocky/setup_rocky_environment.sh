#!/bin/bash
# Rocky Linux Build Environment Setup
set -euo pipefail

echo "Setting up Rocky Linux build environment..."

# Install RPM build tools (available packages only - Phase 3 lesson)
dnf install -y rpm-build rpmdevtools rpmlint createrepo_c || {
    echo "WARNING: Some RPM tools not available, using alternatives"
}

# Setup RPM build environment
rpmdev-setuptree
if [[ ! -d ~/rpmbuild ]]; then
    echo "ERROR: RPM build tree creation failed"
    exit 1
fi

# Configure RPM macros for security
cat > ~/.rpmmacros << 'MACROS_EOF'
%_signature gpg
%_gpg_name SecureOS Build Key
%_gpg_path ~/.gnupg
%__gpg /usr/bin/gpg
MACROS_EOF

echo "Rocky Linux build environment setup completed"
