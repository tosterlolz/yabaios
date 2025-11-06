#!/usr/bin/env just --justfile

# YabaiOS build system

set shell := ["fish", "-c"]

# Default recipe
default: build

# Build kernel
build:
    #!/usr/bin/env fish
    mkdir -p zig-out/build zig-out/fs/bin zig-out/iso/boot
    
    echo "[build] assembling boot code"
    nasm -f elf64 src/boot/boot64.asm -o zig-out/build/boot64.o
    nasm -f elf64 src/boot/interrupt_stubs.asm -o zig-out/build/interrupt_stubs.o
    
    echo "[build] compiling kernel"
    zig build-obj -target x86_64-freestanding-none -O ReleaseSmall -femit-bin=zig-out/kernel.o src/kernel/kernel.zig
    
    echo "[build] building libc stub"
    x86_64-elf-gcc -c -fno-builtin -nostdlib -fno-stack-protector -o zig-out/libc_stub.o libc_stub.c
    
    echo "[build] linking kernel ELF"
    x86_64-elf-ld -T linker.ld -o zig-out/build/kernel.elf zig-out/build/boot64.o zig-out/kernel.o zig-out/build/interrupt_stubs.o zig-out/libc_stub.o
    
    echo "[build] kernel produced: zig-out/build/kernel.elf"

# Build user programs
programs:
    #!/usr/bin/env fish
    mkdir -p zig-out/fs/bin
    
    echo "[programs] building user programs"
    zig build-exe -target x86_64-freestanding-none -O ReleaseSmall src/programs/hello.zig -fno-strip -o zig-out/fs/bin/hello 2>/dev/null || true
    
    echo "[programs] creating initfs image"
    genext2fs -B 4096 -d zig-out/fs -b 1024 zig-out/initfs.img 2>/dev/null || dd if=/dev/zero of=zig-out/initfs.img bs=1M count=1

# Create bootable ISO
iso: build programs
    #!/usr/bin/env fish
    mkdir -p zig-out/build zig-out/fs/bin zig-out/iso/boot/grub
    
    echo "[iso] copying kernel and initfs into zig-out/iso/boot"
    cp zig-out/build/kernel.elf zig-out/iso/boot/kernel.elf
    cp zig-out/initfs.img zig-out/iso/boot/initfs.img
    cp grub.cfg zig-out/iso/boot/grub/grub.cfg 2>/dev/null || true
    
    echo "[iso] creating ISO image with GRUB: zig-out/YabaiOS.iso"
    bash scripts/build-iso.sh zig-out/iso zig-out/YabaiOS.iso xorriso

# Run in QEMU
run: iso
    #!/usr/bin/env fish
    mkdir -p zig-out/build zig-out/fs/bin zig-out/iso/boot
    
    if test ! -f "zig-out/YabaiOS.iso"
        echo "[run] ISO not found, building..."
        just iso
    end
    
    echo "[run] launching qemu"
    qemu-system-x86_64 -m 256 -cdrom zig-out/YabaiOS.iso -serial stdio

# Quick smoke test (compile only, no ISO/QEMU)
smoke: build
    #!/usr/bin/env fish
    echo "[smoke] build successful"

# Clean build artifacts
clean:
    #!/usr/bin/env fish
    echo "[clean] removing zig-out"
    rm -rf zig-out
