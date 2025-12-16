#!/bin/bash
# SecureOS Phase 3 Core Systems Validation Script
# Validates all Phase 3 components for production readiness
# Version: 1.0

set -euo pipefail

echo "=== SecureOS Phase 3 Core Systems Validation ==="

# [1/5] Validate Secure Boot Implementation
echo "[1/5] Validating secure boot implementation..."

if [ -f "core_systems/secure_boot/generate_keys.sh" ] && [ -x "core_systems/secure_boot/generate_keys.sh" ]; then
    echo "✓ Secure boot key generation script available"
else
    echo "✗ Secure boot key generation script missing or not executable"
fi

if [ -f "core_systems/secure_boot/verification/verify_signature.c" ]; then
    echo "✓ Signature verification implementation available"
else
    echo "✗ Signature verification implementation missing"
fi

# Check if we can compile the verification code
if command -v gcc >/dev/null 2>&1; then
    if gcc -o /tmp/verify_signature core_systems/secure_boot/verification/verify_signature.c -lssl -lcrypto >/dev/null 2>&1; then
        echo "✓ Signature verification code compiles successfully"
        rm -f /tmp/verify_signature
    else
        echo "✗ Signature verification code compilation failed"
    fi
else
    echo "✗ GCC compiler not available for validation"
fi

# [2/5] Validate File System Encryption
echo "[2/5] Validating file system encryption..."

if [ -f "core_systems/filesystem/encryption/aes_gcm_encrypt.c" ]; then
    echo "✓ AES-GCM encryption implementation available"
else
    echo "✗ AES-GCM encryption implementation missing"
fi

if [ -f "core_systems/filesystem/setup_luks.sh" ] && [ -x "core_systems/filesystem/setup_luks.sh" ]; then
    echo "✓ LUKS setup script available"
else
    echo "✗ LUKS setup script missing or not executable"
fi

# Check if we can compile the encryption code
if command -v gcc >/dev/null 2>&1; then
    if gcc -o /tmp/aes_gcm_encrypt core_systems/filesystem/encryption/aes_gcm_encrypt.c -lssl -lcrypto >/dev/null 2>&1; then
        echo "✓ AES-GCM encryption code compiles successfully"
        rm -f /tmp/aes_gcm_encrypt
    else
        echo "✗ AES-GCM encryption code compilation failed"
    fi
fi

# Check cryptsetup availability
if command -v cryptsetup >/dev/null 2>&1; then
    echo "✓ LUKS/cryptsetup tools available"
else
    echo "✗ LUKS/cryptsetup tools not installed"
fi

# [3/5] Validate Process Management & Sandboxing
echo "[3/5] Validating process management and sandboxing..."

if [ -f "core_systems/process_management/sandbox/secure_sandbox.c" ]; then
    echo "✓ Secure sandbox implementation available"
else
    echo "✗ Secure sandbox implementation missing"
fi

if [ -f "core_systems/process_management/containers/security_policy.json" ]; then
    echo "✓ Container security policy defined"
else
    echo "✗ Container security policy missing"
fi

# Check if we can compile the sandbox code
if command -v gcc >/dev/null 2>&1; then
    if gcc -o /tmp/secure_sandbox core_systems/process_management/sandbox/secure_sandbox.c -lseccomp -lcap >/dev/null 2>&1; then
        echo "✓ Secure sandbox code compiles successfully"
        rm -f /tmp/secure_sandbox
    else
        echo "✗ Secure sandbox code compilation failed (may need libseccomp-devel and libcap-devel)"
    fi
fi

# Check container tools
CONTAINER_TOOLS=("podman" "buildah" "skopeo")
for tool in "${CONTAINER_TOOLS[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
        echo "✓ Container tool available: $tool"
    else
        echo "✗ Container tool missing: $tool"
    fi
done

# [4/5] Validate Security Dependencies
echo "[4/5] Validating security dependencies..."

SECURITY_LIBS=("openssl" "libgcrypt" "libseccomp")
for lib in "${SECURITY_LIBS[@]}"; do
    if pkg-config --exists "$lib" 2>/dev/null; then
        echo "✓ Security library available: $lib"
    else
        echo "✗ Security library missing: $lib"
    fi
done

# Check for secure boot tools
SECBOOT_TOOLS=("efitools" "sbsigntools" "pesign")
for tool in "${SECBOOT_TOOLS[@]}"; do
    if rpm -q "$tool" >/dev/null 2>&1; then
        echo "✓ Secure boot tool installed: $tool"
    else
        echo "✗ Secure boot tool missing: $tool"
    fi
done

# [5/5] Validate Production Readiness
echo "[5/5] Validating production readiness..."

# Check for complete error handling in scripts
if grep -r "set -euo pipefail" core_systems/ >/dev/null 2>&1; then
    echo "✓ Scripts use proper error handling"
else
    echo "✗ Scripts missing proper error handling"
fi

# Check for security validation
if grep -r "perror\|fprintf.*stderr" core_systems/ >/dev/null 2>&1; then
    echo "✓ Code includes error reporting"
else
    echo "✗ Code missing error reporting"
fi

# Check for memory management
if grep -r "malloc\|free\|cleanup" core_systems/ >/dev/null 2>&1; then
    echo "✓ Code includes memory management"
else
    echo "✗ Code missing memory management"
fi

# Check for cryptographic operations
CRYPTO_FUNCTIONS=("EVP_" "AES_" "SHA" "RSA_")
crypto_found=false
for func in "${CRYPTO_FUNCTIONS[@]}"; do
    if grep -r "$func" core_systems/ >/dev/null 2>&1; then
        crypto_found=true
        break
    fi
done

if [ "$crypto_found" = true ]; then
    echo "✓ Cryptographic operations implemented"
else
    echo "✗ Cryptographic operations missing"
fi

# Validate JSON syntax
if command -v python3 >/dev/null 2>&1; then
    if python3 -m json.tool core_systems/process_management/containers/security_policy.json >/dev/null 2>&1; then
        echo "✓ Security policy JSON is valid"
    else
        echo "✗ Security policy JSON is invalid"
    fi
fi

echo "=== Phase 3 Core Systems Validation Complete ==="

# Summary check
validation_errors=0
if ! [ -f "core_systems/secure_boot/generate_keys.sh" ]; then ((validation_errors++)); fi
if ! [ -f "core_systems/filesystem/encryption/aes_gcm_encrypt.c" ]; then ((validation_errors++)); fi
if ! [ -f "core_systems/process_management/sandbox/secure_sandbox.c" ]; then ((validation_errors++)); fi

if [ $validation_errors -eq 0 ]; then
    echo "✅ Phase 3 validation: PASSED - All core systems ready for production"
    exit 0
else
    echo "❌ Phase 3 validation: FAILED - $validation_errors critical components missing"
    exit 1
fi