#!/bin/bash
set -euo pipefail

DEVICE="$1"
MOUNT_POINT="$2"

if [ $# -ne 2 ]; then
    echo "Usage: $0 <device> <mount_point>"
    exit 1
fi

# Create LUKS2 encrypted partition
cryptsetup luksFormat --type luks2 \
    --cipher aes-xts-plain64 \
    --key-size 512 \
    --hash sha512 \
    --pbkdf argon2id \
    --use-random \
    "$DEVICE"

# Open encrypted device
MAPPER_NAME="secureos_$(basename "$DEVICE")"
cryptsetup luksOpen "$DEVICE" "$MAPPER_NAME"

# Create ext4 filesystem with encryption
mkfs.ext4 -F -E encrypt "/dev/mapper/$MAPPER_NAME"

# Mount with security options
mkdir -p "$MOUNT_POINT"
mount -o nodev,nosuid,noexec "/dev/mapper/$MAPPER_NAME" "$MOUNT_POINT"

echo "Encrypted filesystem created and mounted at $MOUNT_POINT"
