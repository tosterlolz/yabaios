#include "vga.h"
#include <stddef.h>
#include <stdbool.h>
#include <stdint.h>
#include "../io/string.h"
#include "font8x8_basic.h"

#define VGA_WIDTH 80
#define VGA_HEIGHT 25
#define FB_CHAR_WIDTH 8
#define FB_CHAR_HEIGHT 16

static uint16_t *VGA_MEMORY = (uint16_t *)0xB8000;

static size_t cursor_row = 0;
static size_t cursor_col = 0;
static uint8_t current_fg = VGA_COLOR_LIGHT_GREY;
static uint8_t current_bg = VGA_COLOR_BLACK;
static uint8_t color = 0x0F;

static bool fb_enabled = false;
static uint8_t *fb_base = NULL;
static uint32_t fb_pitch = 0;
static uint32_t fb_width = 0;
static uint32_t fb_height = 0;
static uint32_t fb_bytes_per_pixel = 0;
static size_t fb_cols = 0;
static size_t fb_rows = 0;
static uint8_t fb_red_position = 16;
static uint8_t fb_red_mask_size = 8;
static uint8_t fb_green_position = 8;
static uint8_t fb_green_mask_size = 8;
static uint8_t fb_blue_position = 0;
static uint8_t fb_blue_mask_size = 8;
static uint32_t fb_fore_color = 0x00FFFFFF;
static uint32_t fb_back_color = 0x00000000;

static const uint8_t fb_palette_rgb[16][3] = {
    {0x00, 0x00, 0x00}, {0x00, 0x00, 0xAA}, {0x00, 0xAA, 0x00}, {0x00, 0xAA, 0xAA},
    {0xAA, 0x00, 0x00}, {0xAA, 0x00, 0xAA}, {0xAA, 0x55, 0x00}, {0xAA, 0xAA, 0xAA},
    {0x55, 0x55, 0x55}, {0x55, 0x55, 0xFF}, {0x55, 0xFF, 0x55}, {0x55, 0xFF, 0xFF},
    {0xFF, 0x55, 0x55}, {0xFF, 0x55, 0xFF}, {0xFF, 0xFF, 0x55}, {0xFF, 0xFF, 0xFF}
};

static inline uint8_t vga_entry_color(uint8_t fg, uint8_t bg) {
    return (fg & 0x0F) | ((bg & 0x0F) << 4);
}

static inline uint16_t vga_entry(unsigned char uc, uint8_t color_value) {
    return (uint16_t)uc | (uint16_t)color_value << 8;
}

static inline uint32_t scale_component(uint8_t value, uint8_t mask_size) {
    if (mask_size == 0)
        return 0;
    uint32_t max_value = (1u << mask_size) - 1u;
    return (value * max_value + 127u) / 255u;
}

static uint32_t fb_pack_color(uint8_t r, uint8_t g, uint8_t b) {
    uint32_t value = 0;
    if (fb_red_mask_size) {
        uint32_t red = scale_component(r, fb_red_mask_size) & ((1u << fb_red_mask_size) - 1u);
        value |= red << fb_red_position;
    }
    if (fb_green_mask_size) {
        uint32_t green = scale_component(g, fb_green_mask_size) & ((1u << fb_green_mask_size) - 1u);
        value |= green << fb_green_position;
    }
    if (fb_blue_mask_size) {
        uint32_t blue = scale_component(b, fb_blue_mask_size) & ((1u << fb_blue_mask_size) - 1u);
        value |= blue << fb_blue_position;
    }
    return value;
}

static inline uint32_t fb_pack_index(uint8_t index) {
    index &= 0x0F;
    return fb_pack_color(fb_palette_rgb[index][0], fb_palette_rgb[index][1], fb_palette_rgb[index][2]);
}

static void fb_update_dimensions(void) {
    fb_cols = fb_width / FB_CHAR_WIDTH;
    fb_rows = fb_height / FB_CHAR_HEIGHT;
    if (fb_cols == 0)
        fb_cols = 1;
    if (fb_rows == 0)
        fb_rows = 1;
}

static void fb_update_palette(void) {
    fb_fore_color = fb_pack_index(current_fg);
    fb_back_color = fb_pack_index(current_bg);
}

static void fb_draw_char(char c, size_t row, size_t col) {
    if (row >= fb_rows || col >= fb_cols)
        return;

    uint32_t x0 = (uint32_t)col * FB_CHAR_WIDTH;
    uint32_t y0 = (uint32_t)row * FB_CHAR_HEIGHT;

    unsigned char index = (unsigned char)c;
    for (uint32_t y = 0; y < FB_CHAR_HEIGHT; ++y) {
        uint8_t glyph = font8x8_basic[index][y / 2];
        uint32_t *dst = (uint32_t *)(fb_base + (y0 + y) * fb_pitch + x0 * fb_bytes_per_pixel);
        for (uint32_t x = 0; x < FB_CHAR_WIDTH; ++x) {
            uint8_t mask = (uint8_t)(1u << (7u - x));
            dst[x] = (glyph & mask) ? fb_fore_color : fb_back_color;
        }
    }
}

static void fb_scroll(void) {
    if (fb_rows <= 1)
        return;

    const uint32_t char_height_pixels = FB_CHAR_HEIGHT;
    const uint32_t active_height = (uint32_t)fb_rows * FB_CHAR_HEIGHT;
    const uint32_t bytes_per_char_row = fb_pitch * char_height_pixels;
    const uint32_t bytes_to_copy = fb_pitch * (active_height - char_height_pixels);

    memmove(fb_base, fb_base + bytes_per_char_row, bytes_to_copy);

    uint8_t *start = fb_base + bytes_to_copy;
    for (uint32_t y = 0; y < char_height_pixels; ++y) {
        uint32_t *dst = (uint32_t *)(start + y * fb_pitch);
        for (uint32_t x = 0; x < fb_width; ++x) {
            dst[x] = fb_back_color;
        }
    }

    cursor_row = fb_rows - 1;
}

static void fb_newline(void) {
    cursor_col = 0;
    cursor_row++;
    if (cursor_row >= fb_rows) {
        fb_scroll();
    }
}

static void fb_put_printable(char c) {
    if ((unsigned char)c < 0x20 && c != ' ')
        c = '?';

    fb_draw_char(c, cursor_row, cursor_col);
    cursor_col++;
    if (cursor_col >= fb_cols) {
        fb_newline();
    }
}

static void textmode_scroll(void) {
    for (size_t y = 0; y + 1 < VGA_HEIGHT; ++y) {
        for (size_t x = 0; x < VGA_WIDTH; ++x) {
            VGA_MEMORY[y * VGA_WIDTH + x] = VGA_MEMORY[(y + 1) * VGA_WIDTH + x];
        }
    }
    for (size_t x = 0; x < VGA_WIDTH; ++x) {
        VGA_MEMORY[(VGA_HEIGHT - 1) * VGA_WIDTH + x] = vga_entry(' ', color);
    }
    cursor_row = VGA_HEIGHT - 1;
}

void vga_set_color(uint8_t fg, uint8_t bg) {
    current_fg = fg & 0x0F;
    current_bg = bg & 0x0F;
    color = vga_entry_color(current_fg, current_bg);
    if (fb_enabled) {
        fb_update_palette();
    }
}

void vga_init() {
    fb_enabled = false;
    fb_base = NULL;
    fb_pitch = 0;
    fb_width = 0;
    fb_height = 0;
    fb_bytes_per_pixel = 0;
    fb_cols = 0;
    fb_rows = 0;
    cursor_row = 0;
    cursor_col = 0;
    current_fg = VGA_COLOR_LIGHT_GREY;
    current_bg = VGA_COLOR_BLACK;
    color = vga_entry_color(current_fg, current_bg);
    vga_clear();
}

void vga_clear() {
    if (fb_enabled && fb_base) {
        const uint32_t active_height = (uint32_t)fb_rows * FB_CHAR_HEIGHT;
        for (uint32_t y = 0; y < active_height; ++y) {
            uint32_t *dst = (uint32_t *)(fb_base + y * fb_pitch);
            for (uint32_t x = 0; x < fb_width; ++x) {
                dst[x] = fb_back_color;
            }
        }
    } else {
        for (size_t y = 0; y < VGA_HEIGHT; ++y) {
            for (size_t x = 0; x < VGA_WIDTH; ++x) {
                const size_t index = y * VGA_WIDTH + x;
                VGA_MEMORY[index] = vga_entry(' ', color);
            }
        }
    }
    cursor_row = 0;
    cursor_col = 0;
}

void vga_put_char(char c) {
    if (fb_enabled && fb_base) {
        if (c == '\n') {
            fb_newline();
            return;
        }
        if (c == '\r') {
            cursor_col = 0;
            return;
        }
        if (c == '\t') {
            size_t spaces = 4 - (cursor_col % 4);
            for (size_t i = 0; i < spaces; ++i) {
                fb_put_printable(' ');
            }
            return;
        }
        fb_put_printable(c);
        return;
    }

    if (c == '\n') {
        cursor_col = 0;
        cursor_row++;
        if (cursor_row >= VGA_HEIGHT) {
            textmode_scroll();
        }
        return;
    }
    if (c == '\r') {
        cursor_col = 0;
        return;
    }
    if (c == '\t') {
        size_t spaces = 4 - (cursor_col % 4);
        for (size_t i = 0; i < spaces; ++i) {
            vga_put_char(' ');
        }
        return;
    }

    const size_t index = cursor_row * VGA_WIDTH + cursor_col;
    VGA_MEMORY[index] = vga_entry((unsigned char)c, color);
    cursor_col++;
    if (cursor_col >= VGA_WIDTH) {
        cursor_col = 0;
        cursor_row++;
        if (cursor_row >= VGA_HEIGHT) {
            textmode_scroll();
        }
    }
}

void vga_print(const char *str) {
    for (size_t i = 0; str[i] != '\0'; ++i) {
        vga_put_char(str[i]);
    }
}

void vga_backspace() {
    if (fb_enabled && fb_base) {
        if (cursor_col > 0) {
            cursor_col--;
        } else if (cursor_row > 0) {
            cursor_row--;
            cursor_col = fb_cols ? fb_cols - 1 : 0;
        }
        fb_draw_char(' ', cursor_row, cursor_col);
        return;
    }

    if (cursor_col > 0) {
        cursor_col--;
    } else if (cursor_row > 0) {
        cursor_row--;
        cursor_col = VGA_WIDTH - 1;
    }
    const size_t index = cursor_row * VGA_WIDTH + cursor_col;
    VGA_MEMORY[index] = vga_entry(' ', color);
}

bool vga_use_framebuffer(uint64_t addr, uint32_t pitch, uint32_t width, uint32_t height, uint8_t bpp,
                         uint8_t red_position, uint8_t red_mask_size,
                         uint8_t green_position, uint8_t green_mask_size,
                         uint8_t blue_position, uint8_t blue_mask_size) {
    if (addr == 0 || pitch == 0 || width == 0 || height == 0)
        return false;
    if (bpp != 32)
        return false;

    fb_base = (uint8_t *)(uintptr_t)addr;
    fb_pitch = pitch;
    fb_width = width;
    fb_height = height;
    fb_bytes_per_pixel = bpp / 8;
    fb_red_position = red_position;
    fb_red_mask_size = red_mask_size;
    fb_green_position = green_position;
    fb_green_mask_size = green_mask_size;
    fb_blue_position = blue_position;
    fb_blue_mask_size = blue_mask_size;

    fb_enabled = true;
    fb_update_dimensions();
    fb_update_palette();
    cursor_row = 0;
    cursor_col = 0;
    vga_clear();
    return true;
}
