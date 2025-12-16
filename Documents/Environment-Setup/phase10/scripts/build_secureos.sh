#!/bin/bash
# SecureOS Master Build Orchestrator
# Automated build system producing bootable SecureOS images
set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE10_DIR="$(dirname "$SCRIPT_DIR")"
BASE_DIR="$(dirname "$PHASE10_DIR")"
BUILD_LOG="/tmp/secureos_build_$(date +%Y%m%d_%H%M%S).log"

# Source validation functions from Phase 7
if [[ -f "$BASE_DIR/phase7/testing_tools/validation_functions.sh" ]]; then
    source "$BASE_DIR/phase7/testing_tools/validation_functions.sh"
fi

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$BUILD_LOG"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

# Usage function
usage() {
    cat << EOF
Usage: $0 --target=TARGET --format=FORMAT [OPTIONS]

TARGETS:
  lfs     - Linux From Scratch based SecureOS
  rocky   - Rocky Linux based SecureOS  
  both    - Build both LFS and Rocky targets

FORMATS:
  iso     - Bootable ISO image
  vmdk    - VMware VMDK image
  docker  - Docker container image
  all     - All supported formats

OPTIONS:
  --output=FILE         Output file path (for single format)
  --output-dir=DIR      Output directory (for multiple formats)
  --parallel=N          Parallel build jobs (default: nproc)
  --validate           Run comprehensive validation
  --help               Show this help

EXAMPLES:
  $0 --target=lfs --format=iso --output=/tmp/SecureOS-LFS.iso
  $0 --target=rocky --format=vmdk --output=/tmp/SecureOS-Rocky.vmdk
  $0 --target=both --format=all --output-dir=/tmp/SecureOS-Images/
EOF
}

# Parse command line arguments
TARGET=""
FORMAT=""
OUTPUT=""
OUTPUT_DIR=""
PARALLEL_JOBS=$(nproc)
VALIDATE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --target=*)
            TARGET="${1#*=}"
            shift
            ;;
        --format=*)
            FORMAT="${1#*=}"
            shift
            ;;
        --output=*)
            OUTPUT="${1#*=}"
            shift
            ;;
        --output-dir=*)
            OUTPUT_DIR="${1#*=}"
            shift
            ;;
        --parallel=*)
            PARALLEL_JOBS="${1#*=}"
            shift
            ;;
        --validate)
            VALIDATE=true
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            error_exit "Unknown option: $1"
            ;;
    esac
done

# Validate required parameters
[[ -z "$TARGET" ]] && error_exit "Target is required. Use --target=lfs|rocky|both"
[[ -z "$FORMAT" ]] && error_exit "Format is required. Use --format=iso|vmdk|docker|all"

# Validate dependencies from prior phases
validate_dependencies() {
    log "Validating dependencies from prior phases..."
    
    # Check Phase 9 bootstrap environment
    if [[ ! -f "$BASE_DIR/phase9/build_system/lfs/setup_lfs_environment_interactive.sh" ]]; then
        error_exit "Phase 9 LFS environment not found. Run Phase 9 setup first."
    fi
    
    # Check Phase 3-6 security components
    for phase in phase3 phase4 phase5 phase6; do
        if [[ ! -d "$BASE_DIR/$phase" ]]; then
            error_exit "$phase directory not found. Complete prior phases first."
        fi
    done
    
    # Check Phase 7 testing tools
    if [[ ! -d "$BASE_DIR/phase7/testing_tools" ]]; then
        error_exit "Phase 7 testing tools not found. Complete Phase 7 first."
    fi
    
    log "✅ All dependencies validated"
}

# Setup build environment using Phase 9
setup_build_environment() {
    log "Setting up build environment using Phase 9..."
    
    # Source LFS environment if available
    if [[ -f ~/.lfs_env ]]; then
        source ~/.lfs_env
        log "✅ LFS environment loaded"
    else
        log "Setting up LFS environment..."
        cd "$BASE_DIR/phase9/build_system/lfs/"
        ./setup_lfs_environment_interactive.sh --non-interactive --auto-detect
        source ~/.lfs_env
    fi
    
    # Validate build tools
    which gcc || error_exit "GCC not available"
    which make || error_exit "Make not available"
    
    log "✅ Build environment ready"
}

# Build LFS-based SecureOS
build_lfs_secureos() {
    log "Building LFS-based SecureOS..."
    
    cd "$PHASE10_DIR/lfs_automation"
    
    # Download LFS sources with validation
    ./download_lfs_sources.sh --verify-signatures
    
    # Build LFS toolchain
    ./build_lfs_toolchain.sh --parallel="$PARALLEL_JOBS"
    
    # Build LFS system with SecureOS components
    ./build_lfs_system.sh --security-enhanced --integrate-phases=3,4,5,6
    
    log "✅ LFS-based SecureOS built successfully"
}

# Build Rocky Linux-based SecureOS
build_rocky_secureos() {
    log "Building Rocky Linux-based SecureOS..."
    
    cd "$PHASE10_DIR/rocky_automation"
    
    # Setup Rocky build environment
    ./setup_rocky_build.sh --security-enhanced
    
    # Build Rocky kernel with SecureOS patches
    ./build_rocky_kernel.sh --patches=secureos --integrate-phases=3,4
    
    # Package SecureOS components as RPMs
    ./package_secureos_rpms.sh --phases=3,4,5,6
    
    # Assemble Rocky system
    ./assemble_rocky_secureos.sh --base=rocky-9.7
    
    log "✅ Rocky Linux-based SecureOS built successfully"
}

# Generate bootable images
generate_images() {
    local target="$1"
    local format="$2"
    local output_path="$3"
    
    log "Generating $format image for $target target..."
    
    cd "$PHASE10_DIR/image_creation"
    
    case "$format" in
        iso)
            ./generate_iso_image.sh --source="$target" --output="$output_path" --hybrid-boot
            ;;
        vmdk)
            ./generate_vmdk_image.sh --source="$target" --output="$output_path" --size=8G
            ;;
        docker)
            cd "$PHASE10_DIR/image_creation"
            ./create_docker_images.sh --source="$target" --tag="secureos/$target:latest"
            ;;
        *)
            error_exit "Unsupported format: $format"
            ;;
    esac
    
    log "✅ $format image generated successfully"
}

# Main build function
main() {
    log "Starting SecureOS automated build system"
    log "Target: $TARGET, Format: $FORMAT"
    log "Build log: $BUILD_LOG"
    
    # Validate dependencies
    validate_dependencies
    
    # Setup build environment
    setup_build_environment
    
    # Determine output paths
    if [[ "$FORMAT" == "all" ]]; then
        [[ -z "$OUTPUT_DIR" ]] && error_exit "Output directory required for multiple formats"
        mkdir -p "$OUTPUT_DIR"
    else
        [[ -z "$OUTPUT" && -z "$OUTPUT_DIR" ]] && error_exit "Output path required"
        if [[ -n "$OUTPUT_DIR" ]]; then
            mkdir -p "$OUTPUT_DIR"
            case "$FORMAT" in
                iso) OUTPUT="$OUTPUT_DIR/SecureOS-${TARGET}.iso" ;;
                vmdk) OUTPUT="$OUTPUT_DIR/SecureOS-${TARGET}.vmdk" ;;
                docker) OUTPUT="$OUTPUT_DIR" ;;
            esac
        fi
    fi
    
    # Build targets
    case "$TARGET" in
        lfs)
            build_lfs_secureos
            if [[ "$FORMAT" == "all" ]]; then
                generate_images "lfs" "iso" "$OUTPUT_DIR/SecureOS-LFS.iso"
                generate_images "lfs" "vmdk" "$OUTPUT_DIR/SecureOS-LFS.vmdk"
                generate_images "lfs" "docker" "$OUTPUT_DIR"
            else
                generate_images "lfs" "$FORMAT" "$OUTPUT"
            fi
            ;;
        rocky)
            build_rocky_secureos
            if [[ "$FORMAT" == "all" ]]; then
                generate_images "rocky" "iso" "$OUTPUT_DIR/SecureOS-Rocky.iso"
                generate_images "rocky" "vmdk" "$OUTPUT_DIR/SecureOS-Rocky.vmdk"
                generate_images "rocky" "docker" "$OUTPUT_DIR"
            else
                generate_images "rocky" "$FORMAT" "$OUTPUT"
            fi
            ;;
        both)
            build_lfs_secureos
            build_rocky_secureos
            if [[ "$FORMAT" == "all" ]]; then
                generate_images "lfs" "iso" "$OUTPUT_DIR/SecureOS-LFS.iso"
                generate_images "lfs" "vmdk" "$OUTPUT_DIR/SecureOS-LFS.vmdk"
                generate_images "rocky" "iso" "$OUTPUT_DIR/SecureOS-Rocky.iso"
                generate_images "rocky" "vmdk" "$OUTPUT_DIR/SecureOS-Rocky.vmdk"
                cd "$PHASE10_DIR/image_creation"
                ./create_docker_images.sh --source="lfs" --tag="secureos/lfs:latest"
                ./create_docker_images.sh --source="rocky" --tag="secureos/rocky:latest" 2>/dev/null || log "Rocky Docker not yet implemented"
            else
                error_exit "Single format not supported with 'both' target. Use --format=all"
            fi
            ;;
        *)
            error_exit "Invalid target: $TARGET"
            ;;
    esac
    
    # Run validation if requested
    if [[ "$VALIDATE" == "true" ]]; then
        log "Running comprehensive validation..."
        "$SCRIPT_DIR/validate_build_system.sh" --comprehensive --target="$TARGET"
    fi
    
    log "✅ SecureOS build completed successfully"
    log "Build log saved to: $BUILD_LOG"
    
    if [[ -n "$OUTPUT" ]]; then
        log "Output: $OUTPUT"
    elif [[ -n "$OUTPUT_DIR" ]]; then
        log "Output directory: $OUTPUT_DIR"
        ls -la "$OUTPUT_DIR"
    fi
}

# Execute main function
main "$@"