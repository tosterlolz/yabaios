#!/bin/bash
set -e

ISO_DIR="$1"
ISO="$2"
XORRISO="${3:-xorriso}"

mkdir -p "$ISO_DIR/boot/limine"

# Get Limine data directory
LIMINE_DATADIR=$(limine --print-datadir 2>/dev/null || echo "")

if [ -n "$LIMINE_DATADIR" ] && [ -d "$LIMINE_DATADIR" ]; then
    [ -f "$LIMINE_DATADIR/limine-bios-cd.bin" ] && cp "$LIMINE_DATADIR/limine-bios-cd.bin" "$ISO_DIR/boot/limine/" || true
    [ -f "$LIMINE_DATADIR/limine-bios.bin" ] && cp "$LIMINE_DATADIR/limine-bios.bin" "$ISO_DIR/boot/limine/" || true
    [ -f "$LIMINE_DATADIR/limine-bios.sys" ] && cp "$LIMINE_DATADIR/limine-bios.sys" "$ISO_DIR/boot/limine/" || true
    [ -f "$LIMINE_DATADIR/limine-bios.sys" ] && cp "$LIMINE_DATADIR/limine-bios.sys" "$ISO_DIR/" || true
fi

# Determine which boot image to use
IMG=""
if [ -f "$ISO_DIR/boot/limine/limine-bios-cd.bin" ]; then
    IMG="boot/limine/limine-bios-cd.bin"
elif [ -f "$ISO_DIR/boot/limine/limine-bios.bin" ]; then
    IMG="boot/limine/limine-bios.bin"
fi

# Create ISO
if [ -n "$IMG" ]; then
    echo "[iso] using El-Torito image: $IMG"
    "$XORRISO" -as mkisofs -o "$ISO" -b "$IMG" -no-emul-boot -boot-load-size 4 -boot-info-table "$ISO_DIR"
    
    # Run limine installer if available
    if command -v limine >/dev/null 2>&1; then
        limine bios-install "$ISO" || true
    fi
else
    echo "[iso] Limine runtime not found, creating basic ISO"
    "$XORRISO" -as mkisofs -R -J -o "$ISO" "$ISO_DIR"
fi

echo "[iso] done: $ISO"
