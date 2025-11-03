#include "io/log.h"
#include "kb/keyboard.h"
#include "io/shell.h"
#include "fs/fat.h"
#include "vga/vga.h"
#include "multiboot.h"
#include <stdint.h>
#include "io/string.h"

/* Current working directory tracking */
static char current_cwd[256] = "/";

const char *kernel_get_cwd(void) {
    return current_cwd;
}

int kernel_set_cwd(const char *path) {
    if (!path || path[0] == '\0') {
        return -1;
    }

    int len = 0;
    while (path[len] && len < 255) {
        current_cwd[len] = path[len];
        len++;
    }
    current_cwd[len] = '\0';
    return 0;
}

void kernel_main(uint32_t magic, uint32_t addr) {
    log_init();
    log_set_color(VGA_COLOR_LIGHT_GREEN, VGA_COLOR_BLACK);
    log_clear();
    
    /* Welcome banner */
    log_print("\n");
    log_set_color(VGA_COLOR_LIGHT_CYAN, VGA_COLOR_BLACK);
    log_print("╔════════════════════════════════╗\n");
    log_print("║      YabaiOS Kernel v1.0       ║\n");
    log_print("╚════════════════════════════════╝\n");
    log_set_color(VGA_COLOR_LIGHT_GREEN, VGA_COLOR_BLACK);

    multiboot_info_t *mbi = (multiboot_info_t *)addr;

    /* Attempt to initialize framebuffer if available */
    if (mbi->framebuffer_addr != 0 && mbi->framebuffer_width > 0 && mbi->framebuffer_height > 0) {
        uint8_t bpp = (mbi->framebuffer_bpp + 7) / 8;
        if (mbi->framebuffer_type == 1 && bpp == 4) {  /* RGB direct color, 32-bit */
            if (vga_use_framebuffer(
                mbi->framebuffer_addr,
                mbi->framebuffer_pitch,
                mbi->framebuffer_width,
                mbi->framebuffer_height,
                32,
                (uint8_t)mbi->framebuffer_red_field_position,
                (uint8_t)mbi->framebuffer_red_mask_size,
                (uint8_t)mbi->framebuffer_green_field_position,
                (uint8_t)mbi->framebuffer_green_mask_size,
                (uint8_t)mbi->framebuffer_blue_field_position,
                (uint8_t)mbi->framebuffer_blue_mask_size)) {
                log_set_color(VGA_COLOR_LIGHT_YELLOW, VGA_COLOR_BLACK);
                log_print("✓ Framebuffer initialized!\n");
                log_set_color(VGA_COLOR_LIGHT_GREEN, VGA_COLOR_BLACK);
            } else {
                log_set_color(VGA_COLOR_LIGHT_YELLOW, VGA_COLOR_BLACK);
                log_print("✗ Framebuffer init failed, using VGA text mode.\n");
                log_set_color(VGA_COLOR_LIGHT_GREEN, VGA_COLOR_BLACK);
            }
        } else {
            log_set_color(VGA_COLOR_LIGHT_YELLOW, VGA_COLOR_BLACK);
            log_print("✗ Unsupported framebuffer type, using VGA text mode.\n");
            log_set_color(VGA_COLOR_LIGHT_GREEN, VGA_COLOR_BLACK);
        }
    } else {
        log_set_color(VGA_COLOR_LIGHT_YELLOW, VGA_COLOR_BLACK);
        log_print("ℹ No framebuffer info available, using VGA text mode.\n");
        log_set_color(VGA_COLOR_LIGHT_GREEN, VGA_COLOR_BLACK);
    }

    if (mbi->mods_count > 0) {
        log_set_color(VGA_COLOR_LIGHT_BLUE, VGA_COLOR_BLACK);
        log_print("✓ GRUB module found.\n");
        log_set_color(VGA_COLOR_LIGHT_GREEN, VGA_COLOR_BLACK);
        multiboot_module_t *mod = (multiboot_module_t *)mbi->mods_addr;

        void *disk_image = (void *)mod->mod_start;

        if (fat_init(disk_image)) {
            log_set_color(VGA_COLOR_LIGHT_CYAN, VGA_COLOR_BLACK);
            log_print("FAT filesystem mounted.\n");
            log_set_color(VGA_COLOR_LIGHT_GREEN, VGA_COLOR_BLACK);
        }
    } else {
        log_set_color(VGA_COLOR_LIGHT_RED, VGA_COLOR_BLACK);
        log_print("✗ No FAT module found.\n");
        log_set_color(VGA_COLOR_LIGHT_GREEN, VGA_COLOR_BLACK);
    }
    
    log_set_color(VGA_COLOR_LIGHT_CYAN, VGA_COLOR_BLACK);
    log_print("\nInitializing shell...\n");
    log_set_color(VGA_COLOR_LIGHT_GREEN, VGA_COLOR_BLACK);
    keyboard_init();
    shell_init();
    shell_run();
}
