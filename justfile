#!/usr/bin/env just --justfile

# YabaiOS - Zig-based x86_64 OS

set shell := ["fish", "-c"]

# Default recipe
default: build

# Build kernel
build:
    #!/usr/bin/env fish
    mkdir -p zig-out/build zig-out/fs/bin zig-out/iso/boot/grub
    
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
    mkdir -p zig-out/iso/boot/grub
    
    echo "[iso] copying kernel and initfs into zig-out/iso/boot"
    cp zig-out/build/kernel.elf zig-out/iso/boot/kernel.elf
    cp zig-out/initfs.img zig-out/iso/boot/initfs.img
    
    echo "[iso] creating GRUB config"
    printf '%s\n' \
        'menuentry "YabaiOS" {' \
        '    multiboot2 /boot/kernel.elf' \
        '    module2 /boot/initfs.img' \
        '}' > zig-out/iso/boot/grub/grub.cfg
    
    echo "[iso] creating ISO image"
    if command -v grub-mkrescue &> /dev/null
        grub-mkrescue -o zig-out/YabaiOS.iso zig-out/iso 2>/dev/null
        echo "[iso] done: zig-out/YabaiOS.iso"
    else
        echo "[iso] ERROR: grub-mkrescue not found"
        exit 1
    end

# Run in QEMU
run: iso
    #!/usr/bin/env fish
    if test ! -f "zig-out/YabaiOS.iso"
        echo "[run] ISO not found, building..."
        just iso
    end
    
    echo "[run] launching QEMU"
    qemu-system-x86_64 -m 256 -cdrom zig-out/YabaiOS.iso -serial stdio

# Quick smoke test (compile only)
smoke: build
    #!/usr/bin/env fish
    echo "[smoke] build successful"

# Clean build artifacts
clean:
    #!/usr/bin/env fish
    echo "[clean] removing build artifacts"
    rm -rf zig-out build iso *.iso
    echo "[clean] done"

# Run with debugging
debug: iso
    #!/usr/bin/env fish
    echo "[debug] launching QEMU with GDB stub"
    qemu-system-x86_64 -m 256 -cdrom zig-out/YabaiOS.iso -serial stdio -s -S

# Format code with zig fmt
fmt:
    #!/usr/bin/env fish
    echo "[fmt] formatting Zig code"
    find src -name "*.zig" -exec zig fmt {} \;
    echo "[fmt] done"
