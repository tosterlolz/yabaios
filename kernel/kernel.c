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
        log_set_color(VGA_COLOR_LIGHT_YELLOW, VGA_COLOR_BLACK);
        log_print("Framebuffer info: type=");
        log_put_char('0' + mbi->framebuffer_type);
        log_print(" bpp=");
        if (mbi->framebuffer_bpp >= 10) {
            log_put_char('0' + (mbi->framebuffer_bpp / 10));
        }
        log_put_char('0' + (mbi->framebuffer_bpp % 10));
        log_print(" addr=0x");
        log_put_char("0123456789ABCDEF"[(mbi->framebuffer_addr >> 28) & 0xF]);
        log_put_char("0123456789ABCDEF"[(mbi->framebuffer_addr >> 24) & 0xF]);
        log_print("\n");
        log_set_color(VGA_COLOR_LIGHT_GREEN, VGA_COLOR_BLACK);
        
        /* Support RGB direct color (type=1) and indexed color (type=0) framebuffers
         * Type 0: Indexed color (palette)
         * Type 1: RGB direct color
         * Type 2: EGA text
         */
        if (mbi->framebuffer_type == 1 && (mbi->framebuffer_bpp == 32 || mbi->framebuffer_bpp == 24)) {
            /* RGB direct color mode */
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
                log_print("✓ RGB Framebuffer initialized!\n");
                log_set_color(VGA_COLOR_LIGHT_GREEN, VGA_COLOR_BLACK);
            } else {
                log_set_color(VGA_COLOR_LIGHT_YELLOW, VGA_COLOR_BLACK);
                log_print("✗ Framebuffer init failed, using VGA text mode.\n");
                log_set_color(VGA_COLOR_LIGHT_GREEN, VGA_COLOR_BLACK);
            }
        } else if (mbi->framebuffer_type == 0 && mbi->framebuffer_bpp >= 8) {
            /* Indexed color mode - convert to RGB by using default palette */
            log_set_color(VGA_COLOR_LIGHT_YELLOW, VGA_COLOR_BLACK);
            log_print("ℹ Indexed color mode detected (not yet supported), using VGA text.\n");
            log_set_color(VGA_COLOR_LIGHT_GREEN, VGA_COLOR_BLACK);
        } else {
            log_set_color(VGA_COLOR_LIGHT_YELLOW, VGA_COLOR_BLACK);
            log_print("✗ Unsupported framebuffer type=");
            log_put_char('0' + mbi->framebuffer_type);
            log_print(" bpp=");
            if (mbi->framebuffer_bpp >= 10) {
                log_put_char('0' + (mbi->framebuffer_bpp / 10));
            }
            log_put_char('0' + (mbi->framebuffer_bpp % 10));
            log_print(", using VGA text mode.\n");
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
