#!/usr/bin/env just --justfile

set shell := ["bash", "-cu"]

ZIG := env("ZIG", "zig")
NASM := env("NASM", "nasm")
LD := env("LD", "x86_64-elf-ld")
OBJCOPY := env("OBJCOPY", "x86_64-elf-objcopy")
QEMU := env("QEMU", "qemu-system-x86_64")
GENEXT2FS := env("GENEXT2FS", "genext2fs")
XORRISO := env("XORRISO", "xorriso")

# Output paths
ISO_DIR := "zig-out/iso"
ISO := "zig-out/YabaiOS.iso"
KERNEL_ELF := "zig-out/build/kernel.elf"
PROGRAM_IMG := "zig-out/initfs.img"

_init:
    mkdir -p zig-out/build zig-out/fs/bin {{ISO_DIR}}/boot

# Build kernel object files and link kernel
build: _init
    echo "[build] assembling boot64 and interrupt stubs"
    {{NASM}} -f elf64 src/boot/boot64.asm -o zig-out/build/boot64.o
    {{NASM}} -f elf64 src/boot/interrupt_stubs.asm -o zig-out/build/interrupt_stubs.o
    echo "[build] compiling kernel zig -> object"
    {{ZIG}} build-obj -target x86_64-freestanding-none -O ReleaseSmall -femit-bin=zig-out/kernel.o src/kernel/kernel.zig
    echo "[build] building libc stub"
    x86_64-elf-gcc -c -fno-builtin -nostdlib -fno-stack-protector -o zig-out/libc_stub.o libc_stub.c
    echo "[build] linking kernel ELF"
    {{LD}} -T linker.ld -o {{KERNEL_ELF}} zig-out/build/boot64.o zig-out/kernel.o zig-out/build/interrupt_stubs.o zig-out/libc_stub.o
    echo "[build] kernel produced: {{KERNEL_ELF}}"

programs: _init
    echo "[programs] building programs"
    mkdir -p zig-out/fs/bin
    for src in src/programs/*.zig; do \
        [ -f "$src" ] || continue; \
        bin=zig-out/programs/$(basename "${src%.zig}").elf; \
        mkdir -p "$(dirname "$bin")"; \
        {{ZIG}} build-exe -target x86_64-freestanding-none -O ReleaseSmall "$src" -femit-bin="$bin"; \
        cp "$bin" zig-out/fs/bin/; \
    done
    echo "[programs] creating initfs image: {{PROGRAM_IMG}}"
    rm -f {{PROGRAM_IMG}}
    {{GENEXT2FS}} --block-size 1024 --size-in-blocks 512 --root zig-out/fs -f {{PROGRAM_IMG}}

iso: _init
    if [ ! -f "{{KERNEL_ELF}}" ]; then \
        echo "kernel not found, running build first"; \
        just build; \
    fi
    if [ ! -f "{{PROGRAM_IMG}}" ]; then \
        echo "initfs not found, building programs"; \
        just programs; \
    fi
    echo "[iso] copying kernel and initfs into {{ISO_DIR}}/boot"
    cp {{KERNEL_ELF}} {{ISO_DIR}}/boot/kernel.elf
    cp {{PROGRAM_IMG}} {{ISO_DIR}}/boot/initfs.img
    cp limine.conf {{ISO_DIR}}/boot/limine.conf || true
    cp limine.conf {{ISO_DIR}}/limine.conf || true
    echo "[iso] creating ISO image with Limine: {{ISO}}"
    bash scripts/build-iso.sh {{ISO_DIR}} {{ISO}} {{XORRISO}}

run: iso
    echo "[run] launching qemu"
    {{QEMU}} -m 256 -cdrom {{ISO}} -serial stdio

smoke: _init
    echo "[smoke] building kernel"
    just build
    echo "[smoke] building programs"
    just programs
    echo "[smoke] OK"

clean:
    echo "[clean] removing zig-out"
    rm -rf zig-out

[private]
default:
    @echo "Available commands:"
    @echo "  just build      - build kernel object files and link kernel"
    @echo "  just programs   - build programs and create initfs image"
    @echo "  just iso        - build the ISO (depends on build + programs)"
    @echo "  just run        - boot the ISO with qemu (requires ISO)"
    @echo "  just smoke      - quick build: build + programs but skip ISO"
    @echo "  just clean      - remove zig-out"
