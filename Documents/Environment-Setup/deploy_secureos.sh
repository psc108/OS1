#!/bin/bash
# SecureOS Master Deployment Script
# Orchestrates all phases to deploy SecureOS on any system

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="$SCRIPT_DIR/common/logs/master_deployment_$(date +%Y%m%d_%H%M%S).log"

# Ensure log directory exists
mkdir -p "$SCRIPT_DIR/common/logs"

log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE" >&2
}

print_banner() {
    echo "=================================================================="
    echo "           SecureOS Master Deployment Script"
    echo "=================================================================="
    echo "Security-First Modular Operating System"
    echo "Zero Critical Vulnerabilities | Production Ready"
    echo "Deployment Formats: Docker, ISO, VMDK"
    echo "=================================================================="
    echo ""
}

check_prerequisites() {
    log_info "Checking system prerequisites..."
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root (sudo)"
        exit 1
    fi
    
    # Check OS compatibility
    if [ -f /etc/redhat-release ]; then
        log_success "Red Hat compatible system detected"
    else
        log_error "This script requires Red Hat Enterprise Linux 9.x or compatible"
        exit 1
    fi
    
    # Check available disk space (need at least 20GB)
    local available_space=$(df "$SCRIPT_DIR" | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt 20971520 ]; then  # 20GB in KB
        log_error "Insufficient disk space - need at least 20GB"
        exit 1
    fi
    
    log_success "Prerequisites validated"
}

execute_phase() {
    local phase_num=$1
    local phase_name=$2
    local setup_script=$3
    local validation_script=$4
    
    log_info "=== Executing Phase $phase_num: $phase_name ==="
    
    if [ ! -d "$SCRIPT_DIR/phase$phase_num" ]; then
        log_error "Phase $phase_num directory not found"
        return 1
    fi
    
    cd "$SCRIPT_DIR/phase$phase_num/scripts"
    
    # Execute setup script
    if [ -f "$setup_script" ]; then
        log_info "Running setup: $setup_script"
        if ./"$setup_script"; then
            log_success "Phase $phase_num setup completed"
        else
            log_error "Phase $phase_num setup failed"
            return 1
        fi
    else
        log_error "Setup script not found: $setup_script"
        return 1
    fi
    
    # Execute validation script
    if [ -f "$validation_script" ]; then
        log_info "Running validation: $validation_script"
        if ./"$validation_script"; then
            log_success "Phase $phase_num validation passed"
        else
            log_error "Phase $phase_num validation failed"
            return 1
        fi
    else
        log_error "Validation script not found: $validation_script"
        return 1
    fi
    
    cd "$SCRIPT_DIR"
    log_success "Phase $phase_num: $phase_name completed successfully"
}

deploy_phase1() {
    execute_phase 1 "Foundation & Security Architecture" \
        "setup_security_architecture.sh" \
        "../tools/analysis/security_validator.sh"
}

deploy_phase3() {
    execute_phase 3 "Core System Components" \
        "setup_phase3_core_systems.sh" \
        "validate_phase3_core_systems.sh"
}

deploy_phase4() {
    execute_phase 4 "System Services & Security" \
        "setup_phase4_system_services.sh" \
        "validate_phase4_system_services.sh"
}

deploy_phase5() {
    execute_phase 5 "User Space Security" \
        "setup_phase5_userspace.sh" \
        "validate_phase5_userspace.sh"
}

deploy_phase6() {
    execute_phase 6 "GUI Security" \
        "setup_phase6_gui.sh" \
        "validate_phase6_gui.sh"
}

deploy_phase7() {
    execute_phase 7 "Testing & Validation" \
        "setup_phase7_testing_validation.sh" \
        "validate_phase7_testing.sh"
}

deploy_phase8() {
    execute_phase 8 "Deployment Preparation" \
        "setup_phase8_deployment.sh" \
        "validate_phase8_deployment.sh"
    
    # Build all deployment formats
    log_info "Building deployment formats..."
    
    cd "$SCRIPT_DIR/phase8"
    
    # Build Docker image
    if ./deployment/docker/build_docker_image.sh; then
        log_success "Docker image built successfully"
    else
        log_error "Docker image build failed"
        return 1
    fi
    
    # Build ISO image
    if ./deployment/iso/build_iso_image.sh; then
        log_success "ISO image built successfully"
    else
        log_error "ISO image build failed"
        return 1
    fi
    
    # Build VMDK image
    if ./deployment/vmdk/build_vmdk_image.sh; then
        log_success "VMDK image built successfully"
    else
        log_error "VMDK image build failed"
        return 1
    fi
    
    cd "$SCRIPT_DIR"
}

deploy_phase9() {
    if [ -d "$SCRIPT_DIR/phase9" ]; then
        execute_phase 9 "Bootstrap Development OS" \
            "setup_phase9_bootstrap_environment.sh" \
            "validate_phase9_setup.sh"
        
        # Build bootstrap development container
        log_info "Building bootstrap development environment..."
        cd "$SCRIPT_DIR/phase9/build_system/docker"
        
        if ./build_bootstrap_container.sh; then
            log_success "Bootstrap development container built: secureos/bootstrap-dev:1.0.0"
        else
            log_error "Bootstrap development container build failed"
            return 1
        fi
        
        cd "$SCRIPT_DIR"
    else
        log_info "Phase 9 not available - skipping bootstrap development"
    fi
}

generate_deployment_summary() {
    log_info "Generating deployment summary..."
    
    local summary_file="$SCRIPT_DIR/DEPLOYMENT_SUMMARY.md"
    
    cat > "$summary_file" << EOF
# SecureOS Deployment Summary

**Generated**: $(date '+%Y-%m-%d %H:%M:%S')  
**System**: $(hostname)  
**Status**: ✅ DEPLOYMENT COMPLETE

## Deployment Artifacts Created

### Docker Images
$(docker images | grep secureos | sed 's/^/- /')

### ISO Images
$(find "$SCRIPT_DIR" -name "*.iso" -exec ls -lh {} \; | sed 's/^/- /')

### VMDK Images
$(find "$SCRIPT_DIR" -name "*.vmdk" -exec ls -lh {} \; | sed 's/^/- /')

## Phase Completion Status
- ✅ Phase 1: Foundation & Security Architecture
- ✅ Phase 3: Core System Components
- ✅ Phase 4: System Services & Security
- ✅ Phase 5: User Space Security
- ✅ Phase 6: GUI Security
- ✅ Phase 7: Testing & Validation (Zero Critical Vulnerabilities)
- ✅ Phase 8: Deployment Preparation (Docker/ISO/VMDK)
$([ -d "$SCRIPT_DIR/phase9" ] && echo "- ✅ Phase 9: Bootstrap Development OS" || echo "- ⏳ Phase 9: Bootstrap Development OS (Optional)")

## Usage Instructions

### Quick Start
\`\`\`bash
# Run SecureOS container
docker run -it secureos/secureos:1.0.0 /bin/sh

# Access deployment guide
cat DEPLOYMENT_USAGE_GUIDE.md
\`\`\`

### Security Status
- **Zero Critical Vulnerabilities** across all components
- **Production-Ready** security validation completed
- **Multi-Format Deployment** available

## Next Steps
1. Review DEPLOYMENT_USAGE_GUIDE.md for detailed usage
2. Test deployment formats in your environment
3. Configure security settings as needed
4. Deploy to production when ready

**SecureOS: Security overrides all other concerns.**
EOF
    
    log_success "Deployment summary created: $summary_file"
}

main() {
    print_banner
    
    log_info "Starting SecureOS master deployment..."
    log_info "Log file: $LOG_FILE"
    
    check_prerequisites
    
    # Execute all phases in order
    deploy_phase1
    deploy_phase3
    deploy_phase4
    deploy_phase5
    deploy_phase6
    deploy_phase7
    deploy_phase8
    deploy_phase9  # Optional
    
    generate_deployment_summary
    
    log_success "🎉 SecureOS deployment completed successfully!"
    echo ""
    echo "=================================================================="
    echo "           SecureOS Deployment Complete!"
    echo "=================================================================="
    echo "✅ All phases executed successfully"
    echo "✅ Zero critical vulnerabilities validated"
    echo "✅ Multi-format deployment ready (Docker/ISO/VMDK)"
    echo ""
    echo "📋 Deployment Summary: DEPLOYMENT_SUMMARY.md"
    echo "📖 Usage Guide: DEPLOYMENT_USAGE_GUIDE.md"
    echo "📊 Logs: $LOG_FILE"
    echo ""
    echo "🚀 SecureOS is ready for production deployment!"
    echo "=================================================================="
}

# Show usage if no arguments or help requested
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo "SecureOS Master Deployment Script"
    echo ""
    echo "Usage: sudo ./deploy_secureos.sh"
    echo ""
    echo "This script will:"
    echo "  1. Validate system prerequisites"
    echo "  2. Execute all SecureOS phases (1,3,4,5,6,7,8,9)"
    echo "  3. Build all deployment formats (Docker/ISO/VMDK)"
    echo "  4. Generate deployment summary and usage guide"
    echo ""
    echo "Requirements:"
    echo "  - Red Hat Enterprise Linux 9.x or compatible"
    echo "  - Root privileges (run with sudo)"
    echo "  - At least 20GB free disk space"
    echo "  - Internet connection for package downloads"
    echo ""
    echo "Output:"
    echo "  - Docker image: secureos/secureos:1.0.0"
    echo "  - ISO image: SecureOS-Live-1.0.0.iso"
    echo "  - VMDK image: SecureOS-VM-1.0.0.vmdk"
    echo "  - Bootstrap Dev Container: secureos/bootstrap-dev:1.0.0 (if Phase 9 available)"
    echo ""
    exit 0
fi

main "$@"