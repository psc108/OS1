#!/bin/bash
set -euo pipefail

KEY_DIR="$(pwd)/keys"
mkdir -p "$KEY_DIR"

# Generate Platform Key (PK)
openssl req -new -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
    -keyout "$KEY_DIR/PK.key" \
    -out "$KEY_DIR/PK.crt" \
    -subj "/CN=SecureOS Platform Key/"

# Generate Key Exchange Key (KEK)
openssl req -new -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
    -keyout "$KEY_DIR/KEK.key" \
    -out "$KEY_DIR/KEK.crt" \
    -subj "/CN=SecureOS Key Exchange Key/"

# Generate Database Key (db)
openssl req -new -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
    -keyout "$KEY_DIR/db.key" \
    -out "$KEY_DIR/db.crt" \
    -subj "/CN=SecureOS Database Key/"

# Convert to EFI format (use efitools if available, otherwise create manual format)
if command -v cert-to-efi-sig-list >/dev/null 2>&1; then
    cert-to-efi-sig-list -g "$(uuidgen)" "$KEY_DIR/PK.crt" "$KEY_DIR/PK.esl"
    cert-to-efi-sig-list -g "$(uuidgen)" "$KEY_DIR/KEK.crt" "$KEY_DIR/KEK.esl"
    cert-to-efi-sig-list -g "$(uuidgen)" "$KEY_DIR/db.crt" "$KEY_DIR/db.esl"
    
    # Sign with Platform Key
    sign-efi-sig-list -k "$KEY_DIR/PK.key" -c "$KEY_DIR/PK.crt" PK "$KEY_DIR/PK.esl" "$KEY_DIR/PK.auth"
    sign-efi-sig-list -k "$KEY_DIR/PK.key" -c "$KEY_DIR/PK.crt" KEK "$KEY_DIR/KEK.esl" "$KEY_DIR/KEK.auth"
    sign-efi-sig-list -k "$KEY_DIR/KEK.key" -c "$KEY_DIR/KEK.crt" db "$KEY_DIR/db.esl" "$KEY_DIR/db.auth"
else
    echo "efitools not available - keys generated for manual EFI setup"
    echo "Use mokutil or manual UEFI setup to install keys"
    
    # Create simple DER format for manual installation
    openssl x509 -outform DER -in "$KEY_DIR/PK.crt" -out "$KEY_DIR/PK.der"
    openssl x509 -outform DER -in "$KEY_DIR/KEK.crt" -out "$KEY_DIR/KEK.der"
    openssl x509 -outform DER -in "$KEY_DIR/db.crt" -out "$KEY_DIR/db.der"
fi

echo "Secure Boot keys generated successfully"
