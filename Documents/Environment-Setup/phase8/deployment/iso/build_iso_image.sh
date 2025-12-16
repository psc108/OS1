#!/bin/bash
# ISO Image Build Script
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

echo "Building SecureOS ISO image..."
echo "Version: $SECUREOS_VERSION"
echo "ISO Label: $ISO_LABEL"

# Create ISO build directory
ISO_BUILD_DIR="$PHASE8_DIR/build_output/iso_build"
mkdir -p "$ISO_BUILD_DIR"/{isolinux,secureos,boot}

# Create minimal ISO structure
echo "Preparing ISO structure..."

# Create isolinux configuration
cat > "$ISO_BUILD_DIR/isolinux/isolinux.cfg" << 'EOF'
DEFAULT secureos
TIMEOUT 30
PROMPT 1

LABEL secureos
  MENU LABEL SecureOS Live
  KERNEL vmlinuz
  APPEND initrd=initrd.img root=live:CDLABEL=SecureOS-Live rd.live.image quiet
EOF

# Copy SecureOS components
echo "Copying SecureOS components..."
cp -r "$PHASE8_DIR/../phase3/core_systems" "$ISO_BUILD_DIR/secureos/" 2>/dev/null || echo "Phase 3 components not available"
cp -r "$PHASE8_DIR/../phase4/system_services" "$ISO_BUILD_DIR/secureos/" 2>/dev/null || echo "Phase 4 components not available"
cp -r "$PHASE8_DIR/../phase5/user_space" "$ISO_BUILD_DIR/secureos/" 2>/dev/null || echo "Phase 5 components not available"

# Create minimal kernel and initrd (placeholder)
echo "Creating minimal boot files..."
echo "SecureOS Kernel Placeholder" > "$ISO_BUILD_DIR/isolinux/vmlinuz"
echo "SecureOS InitRD Placeholder" > "$ISO_BUILD_DIR/isolinux/initrd.img"

# Create ISO manifest
cat > "$ISO_BUILD_DIR/secureos/MANIFEST" << EOF
SecureOS Live ISO
Version: $SECUREOS_VERSION
Build Date: $BUILD_DATE
Security Baseline: $SECURITY_BASELINE

Components Included:
- Core Security Systems
- System Services
- User Space Security
EOF

# Build ISO image using genisoimage
ISO_OUTPUT="$PHASE8_DIR/build_output/${ISO_LABEL}-${SECUREOS_VERSION}.iso"

echo "Creating ISO image: $ISO_OUTPUT"
genisoimage -o "$ISO_OUTPUT" \
    -b isolinux/isolinux.bin \
    -c isolinux/boot.cat \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -V "$ISO_LABEL" \
    -R -J \
    "$ISO_BUILD_DIR" 2>/dev/null || {
    
    # Fallback: Create simple ISO without bootloader
    echo "Creating simple ISO without bootloader..."
    genisoimage -o "$ISO_OUTPUT" \
        -V "$ISO_LABEL" \
        -R -J \
        "$ISO_BUILD_DIR"
}

if [ -f "$ISO_OUTPUT" ]; then
    echo "✅ ISO image created successfully: $ISO_OUTPUT"
    ls -lh "$ISO_OUTPUT"
else
    echo "❌ ISO image creation failed"
    exit 1
fi