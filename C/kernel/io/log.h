#ifndef LOG_H
#define LOG_H

#include <stdint.h>

void log_init();
void log_message(const char *message);
void log_print(const char *message);
void log_put_char(char c);
void log_putchar(char c);
void log_print_int(int value);
void log_clear();
void log_backspace();
void log_set_color(uint8_t fg, uint8_t bg);
void log_hex(const char *prefix, uint32_t value);

#endif
