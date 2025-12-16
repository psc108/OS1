#!/bin/bash
# LFS Environment Validation Script (Interactive Version)
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_check() {
    echo -e "${BLUE}[CHECK]${NC} $1"
}

VALIDATION_PASSED=true
TOTAL_CHECKS=0
PASSED_CHECKS=0

check_result() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if [[ $1 -eq 0 ]]; then
        log_info "✓ $2"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        log_error "✗ $2"
        VALIDATION_PASSED=false
    fi
}

log_info "Validating LFS environment setup (Interactive Version)..."

# Check if LFS environment file exists and source it
log_check "Checking LFS environment file..."
if [[ -f "$HOME/.lfs_env" ]]; then
    check_result 0 "LFS environment file exists"
    source "$HOME/.lfs_env"
    log_info "Loaded LFS environment: $LFS"
else
    check_result 1 "LFS environment file missing"
    log_error "Please run setup_lfs_environment_interactive.sh first"
    exit 1
fi

# Determine if using external disk
USE_EXTERNAL_DISK=false
if [[ "$LFS" != "/mnt/lfs" ]]; then
    USE_EXTERNAL_DISK=true
fi

# Check main LFS directory
log_check "Checking main LFS directory..."
if [[ -d "$LFS" ]]; then
    check_result 0 "LFS directory exists: $LFS"
else
    check_result 1 "LFS directory missing: $LFS"
fi

# Check if external disk is mounted (if applicable)
if [[ "$USE_EXTERNAL_DISK" == "true" ]]; then
    log_check "Checking external disk mount..."
    mount_point=$(dirname "$LFS")
    if mountpoint -q "$mount_point" 2>/dev/null; then
        check_result 0 "External disk mounted at $mount_point"
    else
        check_result 1 "External disk not properly mounted at $mount_point"
    fi
fi

# Check ownership
log_check "Checking LFS directory ownership..."
if [[ -d "$LFS" ]]; then
    owner=$(stat -c '%U' "$LFS" 2>/dev/null || echo "unknown")
    if [[ "$owner" == "$USER" ]]; then
        check_result 0 "LFS directory owned by $USER"
    else
        check_result 1 "LFS directory owned by $owner, should be $USER"
    fi
else
    check_result 1 "Cannot check ownership - LFS directory missing"
fi

# Check required subdirectories
log_check "Checking LFS subdirectories..."
REQUIRED_DIRS=("$LFS/etc" "$LFS/var" "$LFS/usr/bin" "$LFS/usr/lib" "$LFS/usr/sbin" "$LFS/sources" "$LFS/tools")

for dir in "${REQUIRED_DIRS[@]}"; do
    if [[ -d "$dir" ]]; then
        check_result 0 "Directory exists: $dir"
    else
        check_result 1 "Directory missing: $dir"
    fi
done

# Check symbolic links
log_check "Checking FHS symbolic links..."
REQUIRED_LINKS=("$LFS/bin" "$LFS/lib" "$LFS/sbin")

for link in "${REQUIRED_LINKS[@]}"; do
    if [[ -L "$link" ]]; then
        target=$(readlink "$link")
        expected="usr/$(basename "$link")"
        if [[ "$target" == "$expected" ]]; then
            check_result 0 "Symbolic link correct: $link -> $target"
        else
            check_result 1 "Symbolic link incorrect: $link -> $target (expected: $expected)"
        fi
    else
        check_result 1 "Symbolic link missing: $link"
    fi
done

# Check /tools symlink
log_check "Checking /tools symlink..."
if [[ -L "/tools" ]]; then
    target=$(readlink "/tools")
    if [[ "$target" == "$LFS/tools" ]]; then
        check_result 0 "/tools symlink correct: -> $target"
    else
        check_result 1 "/tools symlink incorrect: -> $target (expected: $LFS/tools)"
    fi
else
    check_result 1 "/tools symlink missing"
fi

# Check sources directory permissions
log_check "Checking sources directory permissions..."
if [[ -d "$LFS/sources" ]]; then
    perms=$(stat -c '%a' "$LFS/sources")
    if [[ "$perms" == "1777" ]]; then
        check_result 0 "Sources directory has correct permissions: $perms"
    else
        check_result 1 "Sources directory has incorrect permissions: $perms (expected: 1777)"
    fi
    
    if [[ -w "$LFS/sources" ]]; then
        check_result 0 "Sources directory is writable"
    else
        check_result 1 "Sources directory is not writable"
    fi
else
    check_result 1 "Sources directory missing"
fi

# Check wrapper scripts
log_check "Checking compiler wrapper scripts..."
WRAPPER_SCRIPTS=("/usr/local/bin/gcc-wrapper" "/usr/local/bin/make-wrapper")

for wrapper in "${WRAPPER_SCRIPTS[@]}"; do
    if [[ -f "$wrapper" ]]; then
        if [[ -x "$wrapper" ]]; then
            check_result 0 "Wrapper script executable: $wrapper"
        else
            check_result 1 "Wrapper script not executable: $wrapper"
        fi
    else
        check_result 1 "Wrapper script missing: $wrapper"
    fi
done

# Check disk space
log_check "Checking available disk space..."
available_space=$(df "$LFS" 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
required_space=$((15 * 1024 * 1024)) # 15GB in KB

if [[ $available_space -gt $required_space ]]; then
    available_gb=$((available_space / 1024 / 1024))
    check_result 0 "Sufficient disk space available: ${available_gb}GB"
else
    available_gb=$((available_space / 1024 / 1024))
    check_result 1 "Insufficient disk space: ${available_gb}GB (required: 15GB)"
fi

# Check environment variables
log_check "Checking environment variables..."
if [[ -n "${LFS:-}" ]]; then
    check_result 0 "LFS variable set: $LFS"
else
    check_result 1 "LFS variable not set"
fi

if [[ -n "${LFS_TGT:-}" ]]; then
    check_result 0 "LFS_TGT variable set: $LFS_TGT"
else
    check_result 1 "LFS_TGT variable not set"
fi

# Check required tools
log_check "Checking required build tools..."
REQUIRED_TOOLS=("gcc" "g++" "make" "patch" "tar" "gzip" "bzip2" "xz")

for tool in "${REQUIRED_TOOLS[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
        version=$(${tool} --version 2>/dev/null | head -n1 || echo "unknown")
        check_result 0 "Tool available: $tool ($version)"
    else
        check_result 1 "Tool missing: $tool"
    fi
done

# Summary
echo
log_info "=== VALIDATION SUMMARY ==="
log_info "Total checks: $TOTAL_CHECKS"
log_info "Passed checks: $PASSED_CHECKS"
log_info "Failed checks: $((TOTAL_CHECKS - PASSED_CHECKS))"

if [[ $VALIDATION_PASSED == true ]]; then
    log_info "✓ LFS environment validation PASSED"
    log_info "Environment is ready for LFS build process"
    
    # Display environment status
    echo
    log_info "=== ENVIRONMENT STATUS ==="
    echo "LFS Directory: $LFS"
    if [[ "$USE_EXTERNAL_DISK" == "true" ]]; then
        echo "Location: External Disk"
    else
        echo "Location: System Disk"
    fi
    echo "Target: ${LFS_TGT:-x86_64-lfs-linux-gnu}"
    echo "Available Space: $((available_space / 1024 / 1024))GB"
    echo "Sources Directory: $LFS/sources"
    echo "Tools Directory: $LFS/tools"
    
    if [[ -f "$LFS/README_LFS_SETUP.md" ]]; then
        echo
        log_info "Setup documentation available at: $LFS/README_LFS_SETUP.md"
    fi
    
    echo
    log_info "To activate the environment:"
    log_info "  source ~/.lfs_env"
    
    exit 0
else
    log_error "✗ LFS environment validation FAILED"
    log_error "Please fix the issues above before proceeding"
    exit 1
fi