#include "vga.h"
#include <stddef.h>

#define VGA_WIDTH 80
#define VGA_HEIGHT 25
static uint16_t *VGA_MEMORY = (uint16_t *)0xB8000;

static size_t cursor_row = 0;
static size_t cursor_col = 0;
static uint8_t color = 0x0F;

static inline uint8_t vga_entry_color(uint8_t fg, uint8_t bg) {
    return fg | bg << 4;
}

static inline uint16_t vga_entry(unsigned char uc, uint8_t color) {
    return (uint16_t) uc | (uint16_t) color << 8;
}

void vga_set_color(uint8_t fg, uint8_t bg) {
    color = vga_entry_color(fg, bg);
}

void vga_init() {
    vga_clear();
}

void vga_clear() {
    for (size_t y = 0; y < VGA_HEIGHT; y++) {
        for (size_t x = 0; x < VGA_WIDTH; x++) {
            const size_t index = y * VGA_WIDTH + x;
            VGA_MEMORY[index] = vga_entry(' ', color);
        }
    }
    cursor_row = 0;
    cursor_col = 0;
}

void vga_put_char(char c) {
    if (c == '\n') {
        cursor_col = 0;
        if (++cursor_row == VGA_HEIGHT)
            cursor_row = 0;
        return;
    }

    const size_t index = cursor_row * VGA_WIDTH + cursor_col;
    VGA_MEMORY[index] = vga_entry(c, color);

    if (++cursor_col == VGA_WIDTH) {
        cursor_col = 0;
        if (++cursor_row == VGA_HEIGHT)
            cursor_row = 0;
    }
}

void vga_print(const char *str) {
    for (size_t i = 0; str[i] != '\0'; i++)
        vga_put_char(str[i]);
}

void vga_backspace() {
    if (cursor_col > 0)
        cursor_col--;
    else if (cursor_row > 0) {
        cursor_row--;
        cursor_col = VGA_WIDTH - 1;
    }
    const size_t index = cursor_row * VGA_WIDTH + cursor_col;
    VGA_MEMORY[index] = vga_entry(' ', color);
}
