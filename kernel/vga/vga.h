#ifndef VGA_VGA_H
#define VGA_VGA_H
#include <stdbool.h>
#include <stdint.h>

enum vga_color {
    VGA_COLOR_BLACK = 0,
    VGA_COLOR_BLUE = 1,
    VGA_COLOR_GREEN = 2,
    VGA_COLOR_CYAN = 3,
    VGA_COLOR_RED = 4,
    VGA_COLOR_MAGENTA = 5,
    VGA_COLOR_BROWN = 6,
    VGA_COLOR_LIGHT_GREY = 7,
    VGA_COLOR_DARK_GREY = 8,
    VGA_COLOR_LIGHT_BLUE = 9,
    VGA_COLOR_LIGHT_GREEN = 10,
    VGA_COLOR_LIGHT_CYAN = 11,
    VGA_COLOR_LIGHT_RED = 12,
    VGA_COLOR_LIGHT_MAGENTA = 13,
    VGA_COLOR_LIGHT_YELLOW = 14,  /* Light Brown is actually Yellow */
    VGA_COLOR_WHITE = 15,
};

void vga_init();
void vga_set_color(uint8_t fg, uint8_t bg);
void vga_put_char(char c);
void vga_print(const char *str);
void vga_clear();
void vga_backspace();
bool vga_use_framebuffer(uint64_t addr, uint32_t pitch, uint32_t width, uint32_t height, uint8_t bpp,
                         uint8_t red_position, uint8_t red_mask_size,
                         uint8_t green_position, uint8_t green_mask_size,
                         uint8_t blue_position, uint8_t blue_mask_size);

#endif
