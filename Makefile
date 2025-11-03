AS = nasm
CC = i686-elf-gcc
LD = i686-elf-ld
QEMU = qemu-system-i386

CFLAGS = -ffreestanding -O2 -Wall -Wextra -fno-exceptions -fno-rtti -nostdlib
LDFLAGS = -T linker.ld

BUILD_DIR = build

SRCS = \
	kernel/kernel.c \
	kernel/vga/vga.c \
	kernel/io/io.c \
	kernel/kb/keyboard.c \
	kernel/io/shell.c \
	kernel/fs/fat.c \
	kernel/io/log.c \
	kernel/io/string.c

# Ensure multiboot header object is linked first so GRUB can find the header
OBJS = $(BUILD_DIR)/multiboot_header.o $(SRCS:kernel/%.c=$(BUILD_DIR)/%.o)

KERNEL_BIN = $(BUILD_DIR)/kernel.elf
ISO_DIR = iso
ISO_NAME = YabaiOS.iso

all: $(ISO_NAME)

$(BUILD_DIR)/multiboot_header.o: boot/multiboot_header.asm
	mkdir -p $(BUILD_DIR)
	$(AS) -f elf32 $< -o $@

$(BUILD_DIR)/%.o: kernel/%.c
	mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(KERNEL_BIN): $(OBJS)
	$(LD) $(LDFLAGS) -o $@ $^

$(ISO_NAME): $(KERNEL_BIN)
	mkdir -p $(ISO_DIR)/boot/grub
	cp $(KERNEL_BIN) $(ISO_DIR)/boot/kernel.elf
	echo 'set timeout=0' > $(ISO_DIR)/boot/grub/grub.cfg
	echo 'set default=0' >> $(ISO_DIR)/boot/grub/grub.cfg
	echo 'menuentry "YabaiOS" { multiboot /boot/kernel.elf }' >> $(ISO_DIR)/boot/grub/grub.cfg
	grub-mkrescue -o $(ISO_NAME) $(ISO_DIR)

run: $(ISO_NAME)
	$(QEMU) -cdrom $(ISO_NAME)

clean:
	rm -rf $(BUILD_DIR) $(ISO_DIR) $(ISO_NAME)

.PHONY: all clean run
