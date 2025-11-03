AS = nasm
CC = i686-elf-gcc
LD = i686-elf-ld
QEMU = qemu-system-i386

CFLAGS = -ffreestanding -O0 -g -Wall -Wextra -fno-exceptions -fno-rtti -nostdlib -I kernel
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
	kernel/io/string.c \
	kernel/io/elf.c

# Ensure multiboot header object is linked first so GRUB can find the header
OBJS = $(BUILD_DIR)/multiboot_header.o $(SRCS:kernel/%.c=$(BUILD_DIR)/%.o)

# core userland programs (built as freestanding ELF blobs and copied into ISO root)
CORE_SRCS := $(wildcard core/*.c)
CORE_OBJS := $(CORE_SRCS:core/%.c=$(BUILD_DIR)/core/%.o)
CORE_ELFS := $(CORE_SRCS:core/%.c=$(BUILD_DIR)/core/%.elf)
FS_IMG := $(BUILD_DIR)/fs.img

# (no embedded initramfs by default; core utils remain standalone)


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

# core build rules
$(BUILD_DIR)/core/%.o: core/%.c
	mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/core/%.elf: $(BUILD_DIR)/core/%.o
	mkdir -p $(dir $@)
	$(LD) -m elf_i386 -Ttext 0x0 --oformat elf32-i386 -o $@ $<

$(KERNEL_BIN): $(OBJS)
	$(LD) $(LDFLAGS) -o $@ $^

# Build ISO: ensure core ELFs are built then copy kernel and core ELFs to ISO
$(ISO_NAME): $(KERNEL_BIN) $(CORE_ELFS) $(FS_IMG)
	mkdir -p $(ISO_DIR)/boot/grub
	cp $(KERNEL_BIN) $(ISO_DIR)/boot/kernel.elf

	# copy core ELF programs and the filesystem image into the ISO so GRUB can load the fs image as a module
	mkdir -p $(ISO_DIR)
	cp $(CORE_ELFS) $(ISO_DIR) || true
	cp $(FS_IMG) $(ISO_DIR)/fs.img || true

	echo 'set timeout=0' > $(ISO_DIR)/boot/grub/grub.cfg
	echo 'set default=0' >> $(ISO_DIR)/boot/grub/grub.cfg
	# Load kernel and also provide the FAT image as a module so the kernel receives it via multiboot modules
	echo 'menuentry "YabaiOS" { ' >> $(ISO_DIR)/boot/grub/grub.cfg
	echo '  multiboot /boot/kernel.elf' >> $(ISO_DIR)/boot/grub/grub.cfg
	echo '  module /fs.img' >> $(ISO_DIR)/boot/grub/grub.cfg
	echo '}' >> $(ISO_DIR)/boot/grub/grub.cfg
	grub-mkrescue -o $(ISO_NAME) $(ISO_DIR)

# (no embedding of core ELFs into kernel; core ELFs remain separate in fs.img)

# Build a FAT image and copy core ELFs into it
$(FS_IMG): $(CORE_ELFS)
	mkdir -p $(dir $@)
	# create empty 4MB image
	dd if=/dev/zero of=$@ bs=1M count=4 >/dev/null 2>&1 || { echo "dd failed"; exit 1; }
	# format as FAT32/VFAT (requires mkfs.vfat from dosfstools)
	mkfs.vfat -n YABAIFS $@ >/dev/null 2>&1 || { echo "mkfs.vfat not found or failed"; exit 1; }
	# copy core ELF files into the image using mtools (mcopy)
	# create /core directory and copy core ELF files into it
	mmd -i $@ ::/core >/dev/null 2>&1 || true
	mcopy -i $@ $(CORE_ELFS) ::/ >/dev/null 2>&1 || { echo "mcopy failed; ensure mtools is installed"; exit 1; }
	mcopy -i $@ $(CORE_ELFS) ::/core/ >/dev/null 2>&1 || { echo "mcopy failed; ensure mtools is installed"; exit 1; }


$(BUILD_DIR)/core/%.o: core/%.c
	mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

run: $(ISO_NAME)
	$(QEMU) -cdrom $(ISO_NAME)

debug: $(ISO_NAME) $(KERNEL_BIN)
	$(QEMU) -cdrom $(ISO_NAME) -s -S &
	sleep 1
	i686-elf-gdb -ex "file $(KERNEL_BIN)" -ex "target remote localhost:1234" -ex "break fat_init" -ex "continue"

fs.img: $(FS_IMG)

clean:
	rm -rf $(BUILD_DIR) $(ISO_DIR) $(ISO_NAME)

.PHONY: all clean run fs.img debug
