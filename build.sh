#!/usr/bin/env bash
set -eu -o pipefail

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT_DIR"

ZIG=${ZIG:-zig}
NASM=${NASM:-nasm}
LD=${LD:-x86_64-elf-ld}
OBJCOPY=${OBJCOPY:-x86_64-elf-objcopy}
QEMU=${QEMU:-qemu-system-x86_64}
GENEXT2FS=${GENEXT2FS:-genext2fs}
XORRISO=${XORRISO:-xorriso}

ISO_DIR=zig-out/iso
ISO=zig-out/YabaiOS.iso
KERNEL_ELF=zig-out/build/kernel.elf
PROGRAM_IMG=zig-out/initfs.img

mkdir -p zig-out/build zig-out/fs/bin $ISO_DIR/boot

prog_help() {
    cat <<EOF
usage: $0 <command>

commands:
  build       build kernel object files and link kernel (produces zig-out/build/kernel.elf)
  programs    build programs and create initfs image (zig-out/initfs.img)
  iso         build the GRUB ISO (depends on build + programs)
  run         boot the ISO with qemu (requires zig-out/YabaiOS.iso)
  clean       remove zig-out
  smoke       quick run: build + programs but skip xorriso/grub
  help        show this message

EOF
}

build_kernel() {
    echo "[build] assembling boot64 and interrupt stubs"
    $NASM -f elf32 src/boot/boot64.asm -o zig-out/build/boot64.o
    $NASM -f elf32 src/boot/interrupt_stubs.asm -o zig-out/build/interrupt_stubs.o

    echo "[build] compiling kernel zig -> object"
    $ZIG build-obj -target i386-freestanding-none -O ReleaseSmall -femit-bin=zig-out/kernel.o src/kernel/kernel.zig

    echo "[build] building libc stub"
    x86_64-elf-gcc -c -fno-builtin -nostdlib -fno-stack-protector -o zig-out/libc_stub.o libc_stub.c

    echo "[build] linking kernel ELF"
    $LD -T linker.ld -o "$KERNEL_ELF" zig-out/build/boot64.o zig-out/kernel.o zig-out/build/interrupt_stubs.o zig-out/libc_stub.o

    echo "[build] kernel produced: $KERNEL_ELF"
}

build_programs_and_initfs() {
    echo "[programs] building programs"
    mkdir -p zig-out/fs/bin
    for src in src/programs/*.zig; do
        [ -f "$src" ] || continue
        bin=zig-out/programs/$(basename "${src%.zig}").elf
        mkdir -p "$(dirname "$bin")"
        $ZIG build-exe -target x86_64-freestanding-none -O ReleaseSmall "$src" -femit-bin="$bin"
        cp "$bin" zig-out/fs/bin/
    done

    echo "[programs] creating initfs image: $PROGRAM_IMG"
    rm -f "$PROGRAM_IMG"
    $GENEXT2FS --block-size 1024 --size-in-blocks 512 --root zig-out/fs -f "$PROGRAM_IMG"
}

build_iso() {
    if [ ! -f "$KERNEL_ELF" ]; then
        echo "kernel not found, running build first"
        build_kernel
    fi
    if [ ! -f "$PROGRAM_IMG" ]; then
        echo "initfs not found, building programs"
        build_programs_and_initfs
    fi

    echo "[iso] copying kernel and initfs into $ISO_DIR/boot"
    cp "$KERNEL_ELF" "$ISO_DIR/boot/kernel.elf"
    cp "$PROGRAM_IMG" "$ISO_DIR/boot/initfs.img"
    cp limine.cfg "$ISO_DIR/boot/limine.cfg" || true
    cp limine.cfg "$ISO_DIR/limine.cfg" || true

    echo "[iso] attempting to include limine boot files if available"
    LIMINE_DATADIR=""
    if command -v limine >/dev/null 2>&1; then
        LIMINE_DATADIR=$(limine --print-datadir 2>/dev/null || true)
    fi

    if [ -n "$LIMINE_DATADIR" ] && [ -d "$LIMINE_DATADIR" ]; then
        echo "[iso] found limine datadir: $LIMINE_DATADIR"
        mkdir -p "$ISO_DIR/boot/limine"
        # Copy only the runtime images (avoid copying example configs from the host datadir)
        [ -f "$LIMINE_DATADIR/limine-bios-cd.bin" ] && cp "$LIMINE_DATADIR/limine-bios-cd.bin" "$ISO_DIR/boot/limine/" || true
        [ -f "$LIMINE_DATADIR/limine-bios.bin" ] && cp "$LIMINE_DATADIR/limine-bios.bin" "$ISO_DIR/boot/limine/" || true
        [ -f "$LIMINE_DATADIR/limine-bios-pxe.bin" ] && cp "$LIMINE_DATADIR/limine-bios-pxe.bin" "$ISO_DIR/boot/limine/" || true
        [ -f "$LIMINE_DATADIR/limine-bios-pxe.bin" ] || true
        [ -f "$LIMINE_DATADIR/limine-bios.sys" ] && cp "$LIMINE_DATADIR/limine-bios.sys" "$ISO_DIR/boot/limine/" || true
        [ -f "$LIMINE_DATADIR/limine-uefi-cd.bin" ] && cp "$LIMINE_DATADIR/limine-uefi-cd.bin" "$ISO_DIR/boot/limine/" || true
        # Ensure bios sys is available at top-level as well (some limine setups expect it)
        [ -f "$ISO_DIR/boot/limine/limine-bios.sys" ] && cp "$ISO_DIR/boot/limine/limine-bios.sys" "$ISO_DIR/" || true
        # Copy only our config into the limine dir
        [ -f limine.cfg ] && cp limine.cfg "$ISO_DIR/boot/limine/limine.cfg" || true
    else
        echo "[iso] limine not found on host; will build plain ISO and attempt installer if present"
    fi

    echo "[iso] creating ISO image: $ISO"
    # If grub-mkrescue is available, prefer GRUB (simpler config for multiboot kernels)
    if command -v grub-mkrescue >/dev/null 2>&1; then
        echo "[iso] grub-mkrescue found; building GRUB-based ISO"
        GRUB_DIR="$(pwd)/zig-out/grub_iso"
        rm -rf "$GRUB_DIR"
        mkdir -p "$GRUB_DIR/boot/grub"
        # copy kernel/initrd
        cp "$ISO_DIR/boot/kernel.elf" "$GRUB_DIR/boot/kernel.elf"
        cp "$ISO_DIR/boot/initfs.img" "$GRUB_DIR/boot/initfs.img"
        # write grub.cfg that uses multiboot2
        cat > "$GRUB_DIR/boot/grub/grub.cfg" <<'GRUBCFG'
set timeout=3
set default=0

menuentry "YabaiOS (multiboot2)" {
    multiboot2 /boot/kernel.elf
    module2 /boot/initfs.img
    boot
}
GRUBCFG

        grub-mkrescue -o "$ISO" "$GRUB_DIR" >/dev/null 2>&1 || {
            echo "[iso] grub-mkrescue failed, falling back to limine"
        }
        rm -rf "$GRUB_DIR"
        echo "[iso] done: $ISO (GRUB)"
        return
    fi

    # Fallback: build ISO using limine files copied earlier
    IMG=""
    if [ -f "$ISO_DIR/boot/limine/limine-cd.bin" ]; then
        IMG=boot/limine/limine-cd.bin
    elif [ -f "$ISO_DIR/boot/limine/limine-bios-cd.bin" ]; then
        IMG=boot/limine/limine-bios-cd.bin
    elif [ -f "$ISO_DIR/boot/limine/limine-bios.bin" ]; then
        IMG=boot/limine/limine-bios.bin
    elif [ -f "$ISO_DIR/boot/limine-bios.bin" ]; then
        IMG=boot/limine-bios.bin
    fi

    if [ -n "$IMG" ]; then
        echo "[iso] using El-Torito image: $IMG"
        $XORRISO -as mkisofs -o "$ISO" -b "$IMG" -no-emul-boot -boot-load-size 4 -boot-info-table "$ISO_DIR"
    else
        $XORRISO -as mkisofs -o "$ISO" "$ISO_DIR"
    fi

    # Try installer tools as a best-effort
    if command -v limine-install >/dev/null 2>&1; then
        limine-install "$ISO" || true
    elif command -v limine >/dev/null 2>&1; then
        limine bios-install "$ISO" || true
    fi

    echo "[iso] done: $ISO"
}

run_qemu() {
    if [ ! -f "$ISO" ]; then
        echo "ISO not found, building first"
        build_iso
    fi
    echo "[run] launching qemu"
    $QEMU -m 256 -cdrom "$ISO" -serial stdio
}

case ${1:-help} in
    build)
        build_kernel
        ;;
    programs)
        build_programs_and_initfs
        ;;
    iso)
        build_iso
        ;;
    run)
        run_qemu
        ;;
    smoke)
        build_kernel
        build_programs_and_initfs
        echo "[smoke] OK"
        ;;
    clean)
        echo "[clean] removing zig-out"
        rm -rf zig-out
        ;;
    help|*)
        prog_help
        ;;
esac
