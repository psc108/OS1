#!/bin/bash
# Fix LFS Environment Setup Issues
set -euo pipefail

echo "Fixing LFS environment setup issues..."

# Fix wrapper script permissions
sudo chmod +x /usr/local/bin/gcc-wrapper /usr/local/bin/make-wrapper
echo "Fixed wrapper script permissions"

# Validate the setup
echo "Running validation..."
./validate_lfs_environment_interactive.sh