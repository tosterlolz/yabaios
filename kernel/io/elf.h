#ifndef ELF_H
#define ELF_H

#include <stdint.h>

// Load an ELF32 image from memory buffer 'elf' of size 'elf_size',
// copy its PT_LOAD segments to a temporary execution area and jump to its entry.
// 'argstr' is passed in EBX register to the program (convention used by our core programs).
// This function does not return unless the program returns; use with care.
int elf_run_from_memory(void *elf, uint32_t elf_size, const char *argstr);

// Search embedded initramfs for a filename; returns pointer and size via out params, or NULL if not found.
struct initramfs_entry { const char *name; const uint8_t *data; uint32_t size; };
const struct initramfs_entry *initramfs_find(const char *name);

#endif
