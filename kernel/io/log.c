#include "log.h"
#include "../vga/vga.h"

void log_init() {
    vga_print("Log system initialized.\n");
}

void log_message(const char *message) {
    vga_print("\n[LOG] \"");
    vga_print(message);
    vga_print("\"\n");
}

void log_print(const char *message) {
    vga_print(message);
}

void log_put_char(char c) {
    vga_put_char(c);
}

void log_clear() {
    vga_clear();
}

void log_backspace() {
    vga_backspace();
}

void log_set_color(uint8_t fg, uint8_t bg) {
    vga_set_color(fg, bg);
}

void log_hex(const char *prefix, uint32_t value) {
    log_print(prefix);
    log_print("0x");
    const char *hex = "0123456789ABCDEF";
    for (int i = 28; i >= 0; i -= 4) {
        log_put_char(hex[(value >> i) & 0xF]);
    }
    log_print("\n");
}
