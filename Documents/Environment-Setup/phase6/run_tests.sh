#!/bin/bash
# Phase 6 GUI Security Test Suite

set -euo pipefail

echo "=== Phase 6 GUI Security Test Suite ==="

# Test compilation
echo "Testing compilation..."
make clean
make all

if [ $? -eq 0 ]; then
    echo "✓ All components compiled successfully"
else
    echo "✗ Compilation failed"
    exit 1
fi

# Test basic functionality
echo "Testing basic functionality..."

# Check if binaries exist and are executable
for binary in secure-compositor input-security client-isolation; do
    if [ -x "./$binary" ]; then
        echo "✓ $binary is executable"
    else
        echo "✗ $binary is not executable"
        exit 1
    fi
done

echo "=== All Phase 6 tests passed ==="
