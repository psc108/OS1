#!/bin/bash
# Phase 8 Deployment Validation Script

set -euo pipefail

readonly PHASE8_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly LOG_FILE="$PHASE8_DIR/../common/logs/phase8_validation_$(date +%Y%m%d_%H%M%S).log"

log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE" >&2
}

validate_docker_deployment() {
    log_info "Validating Docker deployment capability..."
    
    # Check Docker installation
    if ! command -v docker &> /dev/null; then
        log_error "Docker not installed"
        return 1
    fi
    
    # Check Docker service
    if ! systemctl is-active --quiet docker; then
        log_error "Docker service not running"
        return 1
    fi
    
    # Validate Dockerfile
    if [ -f "$PHASE8_DIR/deployment/docker/Dockerfile" ]; then
        log_success "Dockerfile exists and ready for build"
    else
        log_error "Dockerfile missing"
        return 1
    fi
    
    # Check build script
    if [ -x "$PHASE8_DIR/deployment/docker/build_docker_image.sh" ]; then
        log_success "Docker build script is executable"
    else
        log_error "Docker build script missing or not executable"
        return 1
    fi
    
    return 0
}

validate_iso_deployment() {
    log_info "Validating ISO deployment capability..."
    
    # Check essential ISO creation tools
    local essential_tools=("genisoimage" "xorriso")
    local optional_tools=("syslinux")
    
    for tool in "${essential_tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            log_success "ISO tool available: $tool"
        else
            log_error "Missing essential ISO tool: $tool"
            return 1
        fi
    done
    
    for tool in "${optional_tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            log_success "ISO tool available: $tool"
        else
            log_info "Optional ISO tool not found: $tool (ISO will be created without bootloader)"
        fi
    done
    
    # Check build script
    if [ -x "$PHASE8_DIR/deployment/iso/build_iso_image.sh" ]; then
        log_success "ISO build script is executable"
    else
        log_error "ISO build script missing or not executable"
        return 1
    fi
    
    return 0
}

validate_vmdk_deployment() {
    log_info "Validating VMDK deployment capability..."
    
    # Check VMDK creation tools
    if command -v qemu-img &> /dev/null; then
        log_success "QEMU image tools available"
    else
        log_error "QEMU image tools missing"
        return 1
    fi
    
    # Check build script
    if [ -x "$PHASE8_DIR/deployment/vmdk/build_vmdk_image.sh" ]; then
        log_success "VMDK build script is executable"
    else
        log_error "VMDK build script missing or not executable"
        return 1
    fi
    
    return 0
}

validate_build_system() {
    log_info "Validating build system..."
    
    # Check build configuration
    if [ -f "$PHASE8_DIR/build_system/build_config.conf" ]; then
        log_success "Build configuration exists"
    else
        log_error "Build configuration missing"
        return 1
    fi
    
    # Check disk space (need at least 10GB)
    local available_space=$(df "$PHASE8_DIR" | awk 'NR==2 {print $4}')
    if [ "$available_space" -gt 10485760 ]; then
        log_success "Sufficient disk space available: $(($available_space / 1024 / 1024))GB"
    else
        log_error "Insufficient disk space - need at least 10GB"
        return 1
    fi
    
    return 0
}

validate_security_requirements() {
    log_info "Validating security requirements..."
    
    # Check security scanning tools
    local security_tools=("clamav" "bandit")
    for tool in "${security_tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            log_success "Security tool available: $tool"
        else
            log_info "Optional security tool not found: $tool"
        fi
    done
    
    # Validate previous phase security results
    local phase7_results=$(find "$PHASE8_DIR/../phase7" -name "security_analysis_*" -type d 2>/dev/null | head -1)
    if [ -n "$phase7_results" ] && [ -d "$phase7_results" ]; then
        log_success "Phase 7 security analysis results available: $(basename "$phase7_results")"
    else
        log_error "Phase 7 security analysis results missing"
        return 1
    fi
    
    return 0
}

run_deployment_tests() {
    log_info "Running deployment capability tests..."
    
    # Test Docker build (dry run)
    if docker info &> /dev/null; then
        log_success "Docker daemon accessible"
    else
        log_error "Cannot access Docker daemon"
        return 1
    fi
    
    # Test file permissions
    local build_scripts=(
        "$PHASE8_DIR/deployment/docker/build_docker_image.sh"
        "$PHASE8_DIR/deployment/iso/build_iso_image.sh"
        "$PHASE8_DIR/deployment/vmdk/build_vmdk_image.sh"
    )
    
    for script in "${build_scripts[@]}"; do
        if [ -x "$script" ]; then
            log_success "Build script executable: $(basename "$script")"
        else
            log_error "Build script not executable: $(basename "$script")"
            return 1
        fi
    done
    
    return 0
}

main() {
    log_info "Starting Phase 8 deployment validation..."
    
    local validation_failed=0
    
    validate_docker_deployment || validation_failed=1
    validate_iso_deployment || validation_failed=1
    validate_vmdk_deployment || validation_failed=1
    validate_build_system || validation_failed=1
    validate_security_requirements || validation_failed=1
    run_deployment_tests || validation_failed=1
    
    if [ $validation_failed -eq 0 ]; then
        log_success "✅ PHASE 8 VALIDATION SUCCESSFUL"
        log_success "✅ Docker deployment capability validated"
        log_success "✅ ISO deployment capability validated"
        log_success "✅ VMDK deployment capability validated"
        log_success "✅ Ready to build all deployment formats"
        log_info "Next: Execute build scripts in deployment/ subdirectories"
        return 0
    else
        log_error "❌ Phase 8 validation failed"
        log_error "Fix the above issues before proceeding with deployment builds"
        return 1
    fi
}

main "$@"