#!/bin/bash
# LFS Environment Setup for Docker Container
set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_info "Setting up LFS environment in Docker container..."

# LFS environment variables
export LFS=/mnt/lfs
export LFS_TGT=x86_64-lfs-linux-gnu
export PATH=/tools/bin:$PATH
export CONFIG_SITE=$LFS/usr/share/config.site

# Create LFS directory structure
log_info "Creating LFS directory structure..."
mkdir -p "$LFS"/{etc,var,usr/{bin,lib,sbin},sources,tools}

# Create symbolic links for FHS compliance
for i in bin lib sbin; do
    if [[ ! -L "$LFS/$i" ]]; then
        ln -sv "usr/$i" "$LFS/$i"
    fi
done

# Setup sources directory with proper permissions
chmod a+wt "$LFS/sources"

# Create /tools symlink
if [[ ! -L "/tools" ]]; then
    ln -sv "$LFS/tools" /
fi

# Create compiler wrappers in LFS tools
mkdir -p "$LFS/tools/bin"

cat > "$LFS/tools/bin/gcc" << 'EOF'
#!/bin/bash
exec /usr/bin/gcc "$@"
EOF
chmod +x "$LFS/tools/bin/gcc"

cat > "$LFS/tools/bin/make" << 'EOF'
#!/bin/bash
exec /usr/bin/make "$@"
EOF
chmod +x "$LFS/tools/bin/make"

# Create environment file
cat > /etc/lfs_env << EOF
export LFS=$LFS
export LFS_TGT=$LFS_TGT
export PATH=/tools/bin:\$PATH
export CONFIG_SITE=\$LFS/usr/share/config.site
export MAKEFLAGS='-j$(nproc)'
EOF

log_info "LFS environment setup completed in Docker container"
log_info "LFS Directory: $LFS"
log_info "Available Space: $(df -h $LFS | awk 'NR==2{print $4}')"