# Makefile for building and packaging the Zig kernel into a bootable ISO

ZIG := zig
NASM := nasm
LD := x86_64-elf-ld
QEMU := qemu-system-x86_64

ROOT_SRC := src/kernel/kernel.zig
ALL_SRCS := $(shell find src -name '*.zig')

PROGRAM_SRCS := $(wildcard src/programs/*.zig)
PROGRAM_ELFS := $(patsubst src/programs/%.zig, zig-out/programs/%.elf, $(PROGRAM_SRCS))

OBJ := zig-out/kernel.o
BOOT_OBJ := zig-out/build/boot64.o
INTERRUPT_STUBS := zig-out/build/interrupt_stubs.o
KERNEL_ELF := zig-out/build/kernel.elf
PROGRAM_IMG := zig-out/initfs.img
ISO_DIR := zig-out/iso
ISO := zig-out/YabaiOS.iso

ZIGFLAGS := build-obj -target x86_64-freestanding-none -O ReleaseSmall -femit-bin=$(OBJ)

.PHONY: all clean run kernel iso

all: $(ISO)

kernel: $(KERNEL_ELF)

iso: $(ISO)

$(OBJ): $(ALL_SRCS)
	@mkdir -p $(dir $@)
	$(ZIG) $(ZIGFLAGS) $(ROOT_SRC)

$(PROGRAM_ELFS): zig-out/programs/%.elf: src/programs/%.zig
	@mkdir -p $(dir $@)
	$(ZIG) build-exe -target x86_64-freestanding-none -O ReleaseSmall $< -femit-bin=$@

$(PROGRAM_IMG): $(PROGRAM_ELFS)
	@mkdir -p zig-out/fs/bin
	cp $(PROGRAM_ELFS) zig-out/fs/bin/
	rm -f $@
	genext2fs --block-size 1024 --size-in-blocks 512 --root zig-out/fs -f $@

$(BOOT_OBJ): ./src/boot/boot64.asm
	@mkdir -p $(dir $@)
	$(NASM) -f elf64 $< -o $@

$(INTERRUPT_STUBS): ./src/boot/interrupt_stubs.asm
	@mkdir -p $(dir $@)
	$(NASM) -f elf64 $< -o $@

zig-out/libc_stub.o: libc_stub.c
	@mkdir -p $(dir $@)
	x86_64-elf-gcc -c -fno-builtin -nostdlib -fno-stack-protector -o $@ $<

$(KERNEL_ELF): $(BOOT_OBJ) $(OBJ) $(INTERRUPT_STUBS) zig-out/libc_stub.o linker.ld
	@mkdir -p $(dir $@)
	$(LD) -T linker.ld -o $@ $(BOOT_OBJ) $(OBJ) $(INTERRUPT_STUBS) zig-out/libc_stub.o

$(ISO): $(KERNEL_ELF) $(PROGRAM_IMG)
	@mkdir -p $(ISO_DIR)/boot/grub
	cp $(KERNEL_ELF) $(ISO_DIR)/boot/kernel.elf
	cp $(PROGRAM_IMG) $(ISO_DIR)/boot/initfs.img
	printf 'set timeout=0\n' > $(ISO_DIR)/boot/grub/grub.cfg
	printf 'menuentry "YabaiOS" {\n' >> $(ISO_DIR)/boot/grub/grub.cfg
	printf '  multiboot2 /boot/kernel.elf\n' >> $(ISO_DIR)/boot/grub/grub.cfg
	printf '  module2 /boot/initfs.img\n' >> $(ISO_DIR)/boot/grub/grub.cfg
	printf '}\n' >> $(ISO_DIR)/boot/grub/grub.cfg
	grub-mkrescue -o $(ISO) $(ISO_DIR) 2>/dev/null

run: $(ISO)
	$(QEMU) -m 256 -cdrom $(ISO) -serial stdio

clean:
	rm -rf zig-out
