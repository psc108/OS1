#!/bin/bash
# LFS Environment Validation Script (External Drive Version)
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

# LFS environment variables (external drive)
export LFS=/mnt/secureos-sda1/lfs
export LFS_TGT=x86_64-lfs-linux-gnu

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

log_info "Validating LFS environment setup (External Drive)..."

# Check external drive mount
log_check "Checking external drive mount..."
if [[ -d "/mnt/secureos-sda1" ]]; then
    check_result 0 "External drive mounted at /mnt/secureos-sda1"
else
    check_result 1 "External drive not mounted at /mnt/secureos-sda1"
fi

# Check if LFS environment file exists
log_check "Checking LFS environment file..."
if [[ -f "$HOME/.lfs_env" ]]; then
    check_result 0 "LFS environment file exists"
    source "$HOME/.lfs_env"
else
    check_result 1 "LFS environment file missing"
fi

# Check main LFS directory
log_check "Checking main LFS directory..."
if [[ -d "$LFS" ]]; then
    check_result 0 "LFS directory exists: $LFS"
else
    check_result 1 "LFS directory missing: $LFS"
fi

# Check ownership
log_check "Checking LFS directory ownership..."
if [[ -d "$LFS" ]]; then
    OWNER=$(stat -c '%U' "$LFS" 2>/dev/null || echo "unknown")
    if [[ "$OWNER" == "$USER" ]]; then
        check_result 0 "LFS directory owned by $USER"
    else
        check_result 1 "LFS directory owned by $OWNER, should be $USER"
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
        TARGET=$(readlink "$link")
        EXPECTED="usr/$(basename "$link")"
        if [[ "$TARGET" == "$EXPECTED" ]]; then
            check_result 0 "Symbolic link correct: $link -> $TARGET"
        else
            check_result 1 "Symbolic link incorrect: $link -> $TARGET (expected: $EXPECTED)"
        fi
    else
        check_result 1 "Symbolic link missing: $link"
    fi
done

# Check /tools symlink
log_check "Checking /tools symlink..."
if [[ -L "/tools" ]]; then
    TARGET=$(readlink "/tools")
    if [[ "$TARGET" == "$LFS/tools" ]]; then
        check_result 0 "/tools symlink correct: -> $TARGET"
    else
        check_result 1 "/tools symlink incorrect: -> $TARGET (expected: $LFS/tools)"
    fi
else
    check_result 1 "/tools symlink missing"
fi

# Check sources directory permissions
log_check "Checking sources directory permissions..."
if [[ -d "$LFS/sources" ]]; then
    PERMS=$(stat -c '%a' "$LFS/sources")
    if [[ "$PERMS" == "1777" ]]; then
        check_result 0 "Sources directory has correct permissions: $PERMS"
    else
        check_result 1 "Sources directory has incorrect permissions: $PERMS (expected: 1777)"
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

# Check disk space on external drive
log_check "Checking available disk space on external drive..."
AVAILABLE_SPACE=$(df "$LFS" 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
REQUIRED_SPACE=$((15 * 1024 * 1024)) # 15GB in KB

if [[ $AVAILABLE_SPACE -gt $REQUIRED_SPACE ]]; then
    AVAILABLE_GB=$((AVAILABLE_SPACE / 1024 / 1024))
    check_result 0 "Sufficient disk space available: ${AVAILABLE_GB}GB"
else
    AVAILABLE_GB=$((AVAILABLE_SPACE / 1024 / 1024))
    check_result 1 "Insufficient disk space: ${AVAILABLE_GB}GB (required: 15GB)"
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
        VERSION=$(${tool} --version 2>/dev/null | head -n1 || echo "unknown")
        check_result 0 "Tool available: $tool ($VERSION)"
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
    echo "LFS Directory: $LFS (External Drive)"
    echo "Target: $LFS_TGT"
    echo "Available Space: $((AVAILABLE_SPACE / 1024 / 1024))GB"
    echo "Sources Directory: $LFS/sources"
    echo "Tools Directory: $LFS/tools"
    
    if [[ -f "$LFS/README_LFS_SETUP.md" ]]; then
        echo
        log_info "Setup documentation available at: $LFS/README_LFS_SETUP.md"
    fi
    
    exit 0
else
    log_error "✗ LFS environment validation FAILED"
    log_error "Please fix the issues above before proceeding"
    exit 1
fi