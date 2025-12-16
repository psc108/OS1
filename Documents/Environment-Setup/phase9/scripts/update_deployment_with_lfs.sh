#!/bin/bash
# Update Deployment Images with LFS Support
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE9_DIR="$(dirname "$SCRIPT_DIR")"

log_info "Updating deployment images with LFS support..."

# Update Docker image
log_info "Building updated Docker image with LFS..."
cd "$PHASE9_DIR/build_system/docker"
docker build -f Dockerfile.bootstrap -t secureos/bootstrap:lfs .

# Test Docker LFS setup
log_info "Testing LFS setup in Docker..."
docker run --rm secureos/bootstrap:lfs /bin/bash -c "
    source /etc/lfs_env
    echo 'LFS: \$LFS'
    echo 'LFS_TGT: \$LFS_TGT'
    ls -la \$LFS/
    test -x \$LFS/tools/bin/gcc && echo 'GCC wrapper: OK'
    test -x \$LFS/tools/bin/make && echo 'Make wrapper: OK'
    echo 'Docker LFS test: PASSED'
"

# Update ISO creation script
log_info "Updating ISO creation script..."
cat >> "$PHASE9_DIR/scripts/create_iso_with_build_env.sh" << 'EOF'

# Add LFS setup to ISO
echo "Adding LFS environment to ISO..."
mkdir -p "$ISO_ROOT/opt/lfs"
cp "$PHASE9_DIR/build_system/lfs/setup_lfs_environment_interactive.sh" "$ISO_ROOT/opt/lfs/"
cp "$PHASE9_DIR/build_system/lfs/validate_lfs_environment_interactive.sh" "$ISO_ROOT/opt/lfs/"

# Create LFS autostart script for ISO
cat > "$ISO_ROOT/opt/lfs/setup_lfs_iso.sh" << 'LFSEOF'
#!/bin/bash
# LFS Setup for ISO Environment
export LFS=/mnt/lfs
mkdir -p $LFS/{etc,var,usr/{bin,lib,sbin},sources,tools}
for i in bin lib sbin; do ln -sf usr/$i $LFS/$i; done
chmod a+wt $LFS/sources
ln -sf $LFS/tools /
echo "LFS environment ready at $LFS"
LFSEOF

chmod +x "$ISO_ROOT/opt/lfs/setup_lfs_iso.sh"
EOF

# Update VMDK creation script
log_info "Updating VMDK creation script..."
cat >> "$PHASE9_DIR/scripts/create_vmdk_with_build_env.sh" << 'EOF'

# Add LFS setup to VMDK
echo "Adding LFS environment to VMDK..."
mkdir -p "$VMDK_MOUNT/opt/lfs"
cp "$PHASE9_DIR/build_system/lfs/setup_lfs_environment_interactive.sh" "$VMDK_MOUNT/opt/lfs/"
cp "$PHASE9_DIR/build_system/lfs/validate_lfs_environment_interactive.sh" "$VMDK_MOUNT/opt/lfs/"

# Create LFS service for VMDK
cat > "$VMDK_MOUNT/etc/systemd/system/lfs-setup.service" << 'LFSEOF'
[Unit]
Description=LFS Environment Setup
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/opt/lfs/setup_lfs_environment_interactive.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
LFSEOF

# Enable LFS service
chroot "$VMDK_MOUNT" systemctl enable lfs-setup.service
EOF

log_info "Deployment images updated with LFS support"
log_info "✅ Docker: secureos/bootstrap:lfs"
log_info "✅ ISO: LFS setup in /opt/lfs/"
log_info "✅ VMDK: LFS service enabled"