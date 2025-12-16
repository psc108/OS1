#!/bin/bash
# SecureOS Phase 9: Bootstrap Environment Validation
# Version: 1.0
# Date: 2025-12-16
# 
# Validates Phase 9 setup following Production Validation Checklist

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

log_failure() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Test function wrapper
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    ((TESTS_TOTAL++))
    log_info "Testing: $test_name"
    
    if eval "$test_command"; then
        log_success "$test_name"
    else
        log_failure "$test_name"
    fi
}

# Validation functions
validate_directory_structure() {
    log_info "Validating Phase 9 directory structure..."
    
    local required_dirs=(
        "scripts"
        "documentation" 
        "build_system"
        "toolchain"
        "build_system/docker"
        "build_system/lfs"
        "build_system/rocky"
    )
    
    for dir in "${required_dirs[@]}"; do
        run_test "Directory exists: $dir" "[[ -d '$dir' ]]"
    done
}

validate_required_scripts() {
    log_info "Validating required scripts exist and are executable..."
    
    local required_scripts=(
        "scripts/setup_phase9_bootstrap_environment.sh"
        "build_system/docker/build_bootstrap_container.sh"
        "build_system/lfs/setup_lfs_environment.sh"
        "build_system/lfs/download_lfs_sources.sh"
        "build_system/rocky/setup_rocky_environment.sh"
        "build_system/rocky/setup_rocky_sources.sh"
        "scripts/validate_build_security.sh"
    )
    
    for script in "${required_scripts[@]}"; do
        run_test "Script exists: $script" "[[ -f '$script' ]]"
        run_test "Script executable: $script" "[[ -x '$script' ]]"
    done
}

validate_security_integration() {
    log_info "Validating security component integration..."
    
    # Check if security components were copied
    local security_dirs=(
        "build_system/core_systems"
        "build_system/system_services"
        "build_system/user_space"
        "build_system/testing_tools"
    )
    
    for dir in "${security_dirs[@]}"; do
        run_test "Security component exists: $dir" "[[ -d '$dir' ]]"
    done
    
    # Check for key security files
    local security_files=(
        "build_system/core_systems/secure_boot.c"
        "build_system/system_services/secure_sandbox_fixed.c"
        "build_system/system_services/capability_syscalls.c"
        "build_system/user_space/package_verification.c"
    )
    
    for file in "${security_files[@]}"; do
        run_test "Security file exists: $file" "[[ -f '$file' ]]"
    done
}

validate_docker_setup() {
    log_info "Validating Docker setup..."
    
    run_test "Docker command available" "command -v docker &> /dev/null"
    run_test "Docker service running" "docker info &> /dev/null"
    run_test "Bootstrap Dockerfile exists" "[[ -f 'build_system/docker/Dockerfile.bootstrap' ]]"
    
    # Check if base SecureOS container exists or can be built
    if docker images | grep -q "secureos/secureos:1.0.0"; then
        log_success "Base SecureOS container available"
        ((TESTS_PASSED++))
    elif [[ -f "../../phase8/deployment/docker/Dockerfile" ]]; then
        log_success "Phase 8 Dockerfile available for building base container"
        ((TESTS_PASSED++))
    else
        log_failure "Neither base container nor Phase 8 Dockerfile available"
        ((TESTS_FAILED++))
    fi
    ((TESTS_TOTAL++))
}

validate_prerequisites() {
    log_info "Validating Phase 9 prerequisites..."
    
    # Check previous phases exist
    local required_phases=("phase3" "phase4" "phase5" "phase7" "phase8")
    for phase in "${required_phases[@]}"; do
        run_test "Required phase exists: $phase" "[[ -d '../../$phase' ]]"
    done
    
    # Check for essential tools
    local required_tools=("gcc" "make" "wget" "git")
    for tool in "${required_tools[@]}"; do
        run_test "Required tool available: $tool" "command -v $tool &> /dev/null"
    done
}

validate_lfs_setup() {
    log_info "Validating LFS build system setup..."
    
    run_test "LFS setup script exists" "[[ -f 'build_system/lfs/setup_lfs_environment.sh' ]]"
    run_test "LFS download script exists" "[[ -f 'build_system/lfs/download_lfs_sources.sh' ]]"
    
    # Check LFS environment variables in scripts
    run_test "LFS variables in setup script" "grep -q 'LFS=/mnt/lfs' build_system/lfs/setup_lfs_environment.sh"
    run_test "LFS target in setup script" "grep -q 'LFS_TGT=x86_64-lfs-linux-gnu' build_system/lfs/setup_lfs_environment.sh"
}

validate_rocky_setup() {
    log_info "Validating Rocky Linux build system setup..."
    
    run_test "Rocky setup script exists" "[[ -f 'build_system/rocky/setup_rocky_environment.sh' ]]"
    run_test "Rocky sources script exists" "[[ -f 'build_system/rocky/setup_rocky_sources.sh' ]]"
    
    # Check for RPM build configuration
    run_test "RPM build setup in script" "grep -q 'rpmdev-setuptree' build_system/rocky/setup_rocky_environment.sh"
    run_test "Rocky sources repo in script" "grep -q 'rocky-sources' build_system/rocky/setup_rocky_sources.sh"
}

validate_security_validation() {
    log_info "Validating security validation setup..."
    
    run_test "Security validation script exists" "[[ -f 'scripts/validate_build_security.sh' ]]"
    run_test "Security validation executable" "[[ -x 'scripts/validate_build_security.sh' ]]"
    
    # Check for Phase 7 integration
    run_test "Phase 7 reference in validation" "grep -q 'phase7' scripts/validate_build_security.sh"
    run_test "Critical vulnerability check" "grep -q 'CRITICAL' scripts/validate_build_security.sh"
}

validate_documentation() {
    log_info "Validating documentation..."
    
    run_test "Phase 9 README exists" "[[ -f 'README.md' ]]"
    run_test "README contains usage instructions" "grep -q 'Usage Instructions' README.md"
    run_test "README contains security requirements" "grep -q 'Security Requirements' README.md"
    run_test "README contains deliverables" "grep -q 'Deliverables' README.md"
}

# Production Validation Checklist compliance
validate_production_compliance() {
    log_info "Validating Production Validation Checklist compliance..."
    
    # Check for no stub implementations
    if find build_system/ -name "*.c" -exec grep -l "TODO\|STUB\|FIXME\|MOCK" {} \; 2>/dev/null | head -1; then
        log_failure "Found stub implementations in code"
        ((TESTS_FAILED++))
    else
        log_success "No stub implementations found"
        ((TESTS_PASSED++))
    fi
    ((TESTS_TOTAL++))
    
    # Check for error handling patterns
    if find build_system/ -name "*.c" -exec grep -l "error_exit\|return -" {} \; 2>/dev/null | head -1; then
        log_success "Error handling patterns found"
        ((TESTS_PASSED++))
    else
        log_failure "No error handling patterns found"
        ((TESTS_FAILED++))
    fi
    ((TESTS_TOTAL++))
    
    # Check for security validation
    if find build_system/ -name "*.c" -exec grep -l "audit_log\|security" {} \; 2>/dev/null | head -1; then
        log_success "Security validation patterns found"
        ((TESTS_PASSED++))
    else
        log_failure "No security validation patterns found"
        ((TESTS_FAILED++))
    fi
    ((TESTS_TOTAL++))
}

# Generate validation report
generate_report() {
    log_info "Generating Phase 9 validation report..."
    
    local report_file="../../common/logs/phase9/validation_report_$(date +%Y%m%d_%H%M%S).txt"
    mkdir -p "$(dirname "$report_file")"
    
    cat > "$report_file" << EOF
SecureOS Phase 9 Bootstrap Environment Validation Report
========================================================
Date: $(date)
Total Tests: $TESTS_TOTAL
Passed: $TESTS_PASSED
Failed: $TESTS_FAILED
Success Rate: $(( TESTS_PASSED * 100 / TESTS_TOTAL ))%

Status: $([ $TESTS_FAILED -eq 0 ] && echo "PASSED" || echo "FAILED")

Validation Categories:
- Directory Structure
- Required Scripts
- Security Integration
- Docker Setup
- Prerequisites
- LFS Setup
- Rocky Linux Setup
- Security Validation
- Documentation
- Production Compliance

$([ $TESTS_FAILED -eq 0 ] && echo "✅ Phase 9 setup validation PASSED - Ready for implementation" || echo "❌ Phase 9 setup validation FAILED - Fix issues before proceeding")
EOF

    log_info "Validation report saved to: $report_file"
}

# Main execution
main() {
    log_info "Starting SecureOS Phase 9 Bootstrap Environment Validation"
    log_info "Date: $(date)"
    
    # Run all validation tests
    validate_directory_structure
    validate_required_scripts
    validate_security_integration
    validate_docker_setup
    validate_prerequisites
    validate_lfs_setup
    validate_rocky_setup
    validate_security_validation
    validate_documentation
    validate_production_compliance
    
    # Generate summary
    echo
    log_info "=== VALIDATION SUMMARY ==="
    log_info "Total Tests: $TESTS_TOTAL"
    log_success "Passed: $TESTS_PASSED"
    if [ $TESTS_FAILED -gt 0 ]; then
        log_failure "Failed: $TESTS_FAILED"
    fi
    
    # Generate report
    generate_report
    
    # Final status
    if [ $TESTS_FAILED -eq 0 ]; then
        log_success "✅ Phase 9 setup validation PASSED - Ready for implementation"
        exit 0
    else
        log_failure "❌ Phase 9 setup validation FAILED - Fix issues before proceeding"
        exit 1
    fi
}

# Execute main function
main "$@"