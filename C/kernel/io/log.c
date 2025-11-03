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

void log_putchar(char c) {
    vga_put_char(c);
}

void log_print_int(int value) {
    if (value == 0) {
        log_put_char('0');
        return;
    }
    
    int is_negative = value < 0;
    if (is_negative) {
        log_put_char('-');
        value = -value;
    }
    
    char buffer[12];
    int idx = 0;
    
    while (value > 0) {
        buffer[idx++] = '0' + (value % 10);
        value /= 10;
    }
    
    // Print in reverse
    for (int i = idx - 1; i >= 0; i--) {
        log_put_char(buffer[i]);
    }
}

