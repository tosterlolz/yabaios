#!/bin/bash
# Build GRUB-based bootable ISO

ISO_DIR="$1"
OUTPUT_ISO="$2"
XORRISO_CMD="${3:-xorriso}"

if [ -z "$ISO_DIR" ] || [ -z "$OUTPUT_ISO" ]; then
    echo "Usage: $0 <iso_dir> <output_iso> [xorriso_cmd]"
    exit 1
fi

# Try grub-mkrescue first (preferred method)
if command -v grub-mkrescue &> /dev/null; then
    echo "[iso] using grub-mkrescue for GRUB-based ISO"
    grub-mkrescue -o "$OUTPUT_ISO" -d /usr/lib/grub/i386-pc "$ISO_DIR" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "[iso] done: $OUTPUT_ISO (GRUB)"
        exit 0
    fi
fi

# Fallback: manual xorriso + grub-mkimage
if command -v xorriso &> /dev/null && command -v grub-mkimage &> /dev/null; then
    echo "[iso] using xorriso + grub-mkimage for GRUB-based ISO"
    
    # Create GRUB image
    grub-mkimage -O i386-pc -o "$ISO_DIR/boot/grub/i386-pc/core.img" \
        -p '(hd0,msdos1)/boot/grub' biosdisk part_msdos ext2 2>/dev/null
    
    # Create ISO
    xorriso -as mkisofs -U -b boot/grub/i386-pc/eltorito.img \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -o "$OUTPUT_ISO" "$ISO_DIR" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "[iso] done: $OUTPUT_ISO (GRUB via xorriso)"
        exit 0
    fi
fi

echo "[iso] ERROR: Cannot create ISO - grub-mkrescue and xorriso not found"
exit 1
