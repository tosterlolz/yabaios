#include "io/log.h"
#include "kb/keyboard.h"
#include "io/shell.h"
#include "fs/fat.h"
#include "io/log.h"
#include <stdint.h>

typedef struct {
    uint32_t flags;
    uint32_t mem_lower;
    uint32_t mem_upper;
    uint32_t boot_device;
    uint32_t cmdline;
    uint32_t mods_count;
    uint32_t mods_addr;
} multiboot_info_t;

typedef struct {
    uint32_t mod_start;
    uint32_t mod_end;
    uint32_t string;
    uint32_t reserved;
} multiboot_module_t;

void kernel_main(uint32_t magic, uint32_t addr) {
    log_init();
    log_set_color(10, 0);
    log_clear();
    log_message("YabaiOS Kernel booted!");

    multiboot_info_t *mbi = (multiboot_info_t *)addr;

    if (mbi->mods_count > 0) {
    log_message("GRUB module found.");
        multiboot_module_t *mod = (multiboot_module_t *)mbi->mods_addr;
        void *disk_image = (void *)mod->mod_start;

        if (fat_init(disk_image)) {
            fat_list_files();
        }
    } else {
    log_message("No FAT module found.");
    }
    log_message("\PS/2 Driver and YabaiShell starting...");
    keyboard_init();
    shell_init();
    shell_run();
}
