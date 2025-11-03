// kernel API available to core programs.
#ifndef KERNEL_KERNEL_H
#define KERNEL_KERNEL_H

#include <stdint.h>
#include "io/log.h"
#include "fs/fat.h"
#include "vga/vga.h"
#include "io/io.h"

struct kernel_api {
    void (*log_print)(const char *);
    void (*log_put_char)(char);
    void (*log_clear)(void);
    void (*log_backspace)(void);
    void (*log_set_color)(uint8_t fg, uint8_t bg);
    int  (*fat_read_file)(const char *filename, void *out_buffer, uint32_t *out_size);
    int  (*fat_write_file)(const char *filename, const void *data, uint32_t size);
};

static inline struct kernel_api *kernel_api(void) {
    struct kernel_api *p;
    __asm__("movl %%esi, %0" : "=r"(p));
    return p;
}

#endif
