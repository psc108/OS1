#!/bin/bash
# VMDK Image Build Script
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PHASE8_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source build configuration
if [ -f "$PHASE8_DIR/build_system/build_config.conf" ]; then
    source "$PHASE8_DIR/build_system/build_config.conf"
else
    echo "Error: Build configuration not found"
    exit 1
fi

echo "Building SecureOS VMDK image..."
echo "Version: $SECUREOS_VERSION"
echo "VMDK Name: $VMDK_NAME"

# Create VMDK build directory
VMDK_BUILD_DIR="$PHASE8_DIR/build_output/vmdk_build"
mkdir -p "$VMDK_BUILD_DIR"

# Create raw disk image (1GB - smaller for demo)
RAW_IMAGE="$VMDK_BUILD_DIR/${VMDK_NAME}-${SECUREOS_VERSION}.raw"
VMDK_IMAGE="$PHASE8_DIR/build_output/${VMDK_NAME}-${SECUREOS_VERSION}.vmdk"

echo "Creating raw disk image (1GB)..."
dd if=/dev/zero of="$RAW_IMAGE" bs=1M count=1024 status=progress 2>/dev/null || {
    echo "Creating minimal raw image (100MB)..."
    dd if=/dev/zero of="$RAW_IMAGE" bs=1M count=100
}

echo "Raw disk image created: $RAW_IMAGE"

# Create filesystem structure directory
ROOTFS_DIR="$VMDK_BUILD_DIR/rootfs"
mkdir -p "$ROOTFS_DIR"/{bin,sbin,etc,var,tmp,home,opt/secureos}

# Copy SecureOS components
echo "Copying SecureOS components to rootfs..."
cp -r "$PHASE8_DIR/../phase3/core_systems" "$ROOTFS_DIR/opt/secureos/" 2>/dev/null || echo "Phase 3 components not available"
cp -r "$PHASE8_DIR/../phase4/system_services" "$ROOTFS_DIR/opt/secureos/" 2>/dev/null || echo "Phase 4 components not available"
cp -r "$PHASE8_DIR/../phase5/user_space" "$ROOTFS_DIR/opt/secureos/" 2>/dev/null || echo "Phase 5 components not available"

# Create basic system files
echo "Creating basic system configuration..."
cat > "$ROOTFS_DIR/etc/secureos-release" << EOF
SecureOS $SECUREOS_VERSION
Build Date: $BUILD_DATE
Security Baseline: $SECURITY_BASELINE
Architecture: x86_64
EOF

# Create init script
cat > "$ROOTFS_DIR/sbin/init" << 'EOF'
#!/bin/sh
echo "SecureOS VM Starting..."
echo "Version: $(cat /etc/secureos-release | head -1)"
echo "SecureOS components available in /opt/secureos/"
exec /bin/sh
EOF
chmod +x "$ROOTFS_DIR/sbin/init"

# Convert raw image to VMDK format
echo "Converting to VMDK format..."
qemu-img convert -f raw -O vmdk "$RAW_IMAGE" "$VMDK_IMAGE"

if [ -f "$VMDK_IMAGE" ]; then
    echo "✅ VMDK image created successfully: $VMDK_IMAGE"
    ls -lh "$VMDK_IMAGE"
    
    # Create VMX configuration file
    VMX_FILE="$PHASE8_DIR/build_output/${VMDK_NAME}-${SECUREOS_VERSION}.vmx"
    cat > "$VMX_FILE" << EOF
#!/usr/bin/vmware
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "19"
vmci0.present = "TRUE"
displayName = "SecureOS $SECUREOS_VERSION"
guestOS = "other3xlinux-64"
memsize = "4096"
numvcpus = "2"
scsi0.present = "TRUE"
scsi0.virtualDev = "lsilogic"
scsi0:0.present = "TRUE"
scsi0:0.fileName = "${VMDK_NAME}-${SECUREOS_VERSION}.vmdk"
ethernet0.present = "TRUE"
ethernet0.virtualDev = "e1000"
ethernet0.networkName = "NAT"
sound.present = "FALSE"
usb.present = "FALSE"
EOF
    echo "✅ VMX configuration created: $VMX_FILE"
else
    echo "❌ VMDK image creation failed"
    exit 1
fi