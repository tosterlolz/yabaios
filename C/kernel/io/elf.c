#include "elf.h"
#include "string.h"
#include "log.h"
#include "../fs/fat.h"
#include "../kernel.h"
#include <stdint.h>
#include <stddef.h>

/* External kernel functions */
extern const char *kernel_get_cwd(void);
extern int kernel_set_cwd(const char *path);

// Simple execution area (1MB)
static uint8_t exec_area[1024*1024];

// Space for argc/argv
#define MAX_ARGV 64
#define ARGV_BUFFER_SIZE 1024
static const char *argv_buffer[MAX_ARGV];
static char argv_strings[ARGV_BUFFER_SIZE];
static struct program_args args_struct;

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

/* Parse argument string into argc/argv array.
 * The shell passes the command name as argv[0], then remaining args.
 * Format: "ls" or "echo hello world"
 */
static int parse_args(const char *argstr) {
    if (!argstr || !*argstr) {
        args_struct.argc = 0;
        args_struct.argv = argv_buffer;
        return 0;
    }

    int argc = 0;
    int buf_offset = 0;
    int in_word = 0;
    int word_start = 0;

    for (int i = 0; argstr[i] != '\0' && argc < MAX_ARGV - 1; i++) {
        char c = argstr[i];

        if (c == ' ' || c == '\t') {
            if (in_word) {
                /* End current word */
                if (buf_offset < ARGV_BUFFER_SIZE) {
                    argv_strings[buf_offset++] = '\0';
                }
                argv_buffer[argc++] = &argv_strings[word_start];
                in_word = 0;
            }
        } else {
            if (!in_word) {
                /* Start new word */
                word_start = buf_offset;
                in_word = 1;
            }
            if (buf_offset < ARGV_BUFFER_SIZE - 1) {
                argv_strings[buf_offset++] = c;
            }
        }
    }

    /* Handle last word */
    if (in_word && buf_offset < ARGV_BUFFER_SIZE) {
        argv_strings[buf_offset++] = '\0';
        argv_buffer[argc++] = &argv_strings[word_start];
    }

    args_struct.argc = argc;
    args_struct.argv = argv_buffer;
    return argc;
}

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
    static struct kernel_api api;
    api.log_print = log_print;
    api.log_put_char = log_put_char;
    api.log_putchar = log_putchar;
    api.log_clear = log_clear;
    api.log_backspace = log_backspace;
    api.log_set_color = log_set_color;
    api.log_print_int = log_print_int;
    api.strlen = strlen;
    api.fat_read_file = (int(*)(const char*,void*,uint32_t*))fat_read_file;
    api.fat_write_file = (int(*)(const char*,const void*,uint32_t))fat_write_file;
    api.fat_list_files = fat_list_files;
    api.get_cwd = kernel_get_cwd;
    api.set_cwd = kernel_set_cwd;
    api.fat_list_files_in_dir = fat_list_files_in_dir;
    api.fat_create_dir = NULL;  // Not implemented yet
    api.fat_delete_file = NULL; // Not implemented yet
    api.fat_copy_file = NULL;   // Not implemented yet
    api.fat_move_file = NULL;   // Not implemented yet

    // Parse arguments
    parse_args(argstr);

    // call entry with EBX = argstr, ESI = &api, and EDX = &args_struct
    // Use memory location to hold function pointer to avoid constraint issues
    void (*entry_func)(void) = entry;
    __asm__ volatile (
        "movl %0, %%ebx\n\t"
        "movl %1, %%esi\n\t"
        "movl %2, %%edx\n\t"
        "call *%3\n\t"
        :
        : "g" (argstr), "g" (&api), "g" (&args_struct), "g" (entry_func)
        : "%ebx", "%esi", "%edx"
    );

    return 0;
}


