#include "elf.h"
#include "string.h"
#include "log.h"
#include "../fs/fat.h"
#include <stdint.h>
#include <stddef.h>

// Simple execution area (1MB)
static uint8_t exec_area[1024*1024];

// Minimal ELF structures
typedef struct {
    unsigned char e_ident[16];
    uint16_t e_type;
    uint16_t e_machine;
    uint32_t e_version;
    uint32_t e_entry;
    uint32_t e_phoff;
    uint32_t e_shoff;
    uint32_t e_flags;
    uint16_t e_ehsize;
    uint16_t e_phentsize;
    uint16_t e_phnum;
    uint16_t e_shentsize;
    uint16_t e_shnum;
    uint16_t e_shstrndx;
} Elf32_Ehdr;

typedef struct {
    uint32_t p_type;
    uint32_t p_offset;
    uint32_t p_vaddr;
    uint32_t p_paddr;
    uint32_t p_filesz;
    uint32_t p_memsz;
    uint32_t p_flags;
    uint32_t p_align;
} Elf32_Phdr;

#define PT_LOAD 1

int elf_run_from_memory(void *elf, uint32_t elf_size, const char *argstr) {
    if (elf_size < sizeof(Elf32_Ehdr)) return -1;
    Elf32_Ehdr *eh = (Elf32_Ehdr *)elf;
    if (eh->e_ident[0] != 0x7F || eh->e_ident[1] != 'E' || eh->e_ident[2] != 'L' || eh->e_ident[3] != 'F')
        return -1;

    // load segments into exec_area
    Elf32_Phdr *ph = (Elf32_Phdr *)((uint8_t *)elf + eh->e_phoff);
    uint32_t base = (uint32_t)exec_area;
    for (int i = 0; i < eh->e_phnum; i++) {
        if (ph[i].p_type != PT_LOAD) continue;
        if (ph[i].p_offset + ph[i].p_filesz > elf_size) return -1;
        uint8_t *dst = (uint8_t *)(base + ph[i].p_vaddr);
        uint8_t *src = (uint8_t *)elf + ph[i].p_offset;
        for (uint32_t k = 0; k < ph[i].p_filesz; k++) dst[k] = src[k];
        for (uint32_t k = ph[i].p_filesz; k < ph[i].p_memsz; k++) dst[k] = 0;
    }

    // compute entry
    void (*entry)(const char *) = (void (*)(const char *))(base + eh->e_entry);

    // prepare kernel API struct and set ESI to point to it for core programs
    static struct kernel_api {
        void (*log_print)(const char *);
        void (*log_put_char)(char);
        void (*log_clear)(void);
        void (*log_backspace)(void);
        void (*log_set_color)(uint8_t fg, uint8_t bg);
        int  (*fat_read_file)(const char *filename, void *out_buffer, uint32_t *out_size);
        int  (*fat_write_file)(const char *filename, const void *data, uint32_t size);
    } api;
    api.log_print = log_print;
    api.log_put_char = log_put_char;
    api.log_clear = log_clear;
    api.log_backspace = log_backspace;
    api.log_set_color = log_set_color;
    api.fat_read_file = (int(*)(const char*,void*,uint32_t*))fat_read_file;
    api.fat_write_file = (int(*)(const char*,const void*,uint32_t))fat_write_file;

    // call entry with EBX = argstr and ESI = &api
    __asm__ volatile (
        "movl %0, %%ebx\n"
        "movl %1, %%esi\n"
        "call *%2\n"
        :
        : "r" (argstr), "r" (&api), "r" (entry)
        : "%ebx", "%esi"
    );

    return 0;
}

