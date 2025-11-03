# Makefile for building and packaging the Zig kernel into a bootable ISO

ZIG := zig
NASM := nasm
LD := i686-elf-ld
GRUBMKRESCUE := grub-mkrescue
QEMU := qemu-system-i386

ROOT_SRC := src/kernel/kernel.zig
ALL_SRCS := $(shell find src -name '*.zig')

PROGRAM_SRCS := $(wildcard src/programs/*.zig)
PROGRAM_ELFS := $(patsubst src/programs/%.zig, zig-out/programs/%.elf, $(PROGRAM_SRCS))

OBJ := zig-out/kernel.o
MULTIBOOT_OBJ := zig-out/build/multiboot_header.o
KERNEL_ELF := zig-out/build/kernel.elf
PROGRAM_IMG := zig-out/initfs.img
ISO_DIR := zig-out/iso
ISO := zig-out/YabaiOS.iso

ZIGFLAGS := build-obj -target x86-freestanding-none -mcpu=i386 -O ReleaseSmall -femit-bin=$(OBJ)

.PHONY: all clean run kernel iso

all: $(ISO)

kernel: $(KERNEL_ELF)

iso: $(ISO)

$(OBJ): $(ALL_SRCS)
	@mkdir -p $(dir $@)
	$(ZIG) $(ZIGFLAGS) $(ROOT_SRC)

$(PROGRAM_ELFS): zig-out/programs/%.elf: src/programs/%.zig
	@mkdir -p $(dir $@)
	$(ZIG) build-exe -target x86-freestanding-none -mcpu=i386 -O ReleaseSmall $< -femit-bin=$@

$(PROGRAM_IMG): $(PROGRAM_ELFS)
	@mkdir -p zig-out/fs/bin
	cp $(PROGRAM_ELFS) zig-out/fs/bin/
	rm -f $@
	genext2fs --block-size 1024 --size-in-blocks 512 --root zig-out/fs -f $@

$(MULTIBOOT_OBJ): ./src/boot/multiboot_header.asm
	@mkdir -p $(dir $@)
	$(NASM) -f elf32 $< -o $@

$(KERNEL_ELF): $(MULTIBOOT_OBJ) $(OBJ) linker.ld
	@mkdir -p $(dir $@)
	$(LD) -T linker.ld -o $@ $(MULTIBOOT_OBJ) $(OBJ)

$(ISO): $(KERNEL_ELF) $(PROGRAM_IMG)
	@mkdir -p $(ISO_DIR)/boot/grub
	cp $(KERNEL_ELF) $(ISO_DIR)/boot/kernel.elf
	cp $(PROGRAM_IMG) $(ISO_DIR)/boot/initfs.img
	printf 'set timeout=0\n' > $(ISO_DIR)/boot/grub/grub.cfg
	printf 'set default=0\n' >> $(ISO_DIR)/boot/grub/grub.cfg
	printf 'insmod gfxterm\n' >> $(ISO_DIR)/boot/grub/grub.cfg
	printf 'insmod vbe\n' >> $(ISO_DIR)/boot/grub/grub.cfg
	printf 'set gfxmode=1280x720x32\n' >> $(ISO_DIR)/boot/grub/grub.cfg
	printf 'set gfxpayload=keep\n' >> $(ISO_DIR)/boot/grub/grub.cfg
	printf 'terminal_output gfxterm\n' >> $(ISO_DIR)/boot/grub/grub.cfg
	printf 'menuentry "YabaiOS" { \n' >> $(ISO_DIR)/boot/grub/grub.cfg
	printf '  multiboot /boot/kernel.elf\n' >> $(ISO_DIR)/boot/grub/grub.cfg
	printf '  module /boot/initfs.img\n' >> $(ISO_DIR)/boot/grub/grub.cfg
	printf '}\n' >> $(ISO_DIR)/boot/grub/grub.cfg
	$(GRUBMKRESCUE) -o $(ISO) $(ISO_DIR)

run: $(ISO)
	$(QEMU) -cdrom $(ISO)

clean:
	rm -rf zig-out
