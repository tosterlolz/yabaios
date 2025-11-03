#include "shell.h"
#include "log.h"
#include "../kb/keyboard.h"
#include "string.h"
#include "io.h"
#include "../fs/fat.h"
#include <stdbool.h>
#include <stddef.h>


#define MAX_INPUT 128

static char input_buffer[MAX_INPUT];
static int input_length = 0;

void shell_prompt() {
    log_print("\n> ");
}

void shell_clear_input() {
    for (int i = 0; i < MAX_INPUT; i++) input_buffer[i] = 0;
    input_length = 0;
}

static int starts_with(const char *s, const char *prefix) {
    int i = 0;
    while (prefix[i]) {
        if (s[i] == '\0') return 0;
        if (s[i] != prefix[i]) return 0;
        i++;
    }
    return 1;
}

void shell_execute() {
    input_buffer[input_length] = '\0';

    if (input_length == 0) return;

    if (!strcmp(input_buffer, "help")) {
    log_print("\nAvailable commands:\n");
    log_print("  help   - show this help message\n");
    log_print("  clear  - clear the screen\n");
    log_print("  about  - info about the OS\n");
    } else if (!strcmp(input_buffer, "clear")) {
    log_clear();
    } else if (!strcmp(input_buffer, "about")) {
    log_print("\nYabaiOS - A simple educational OS\n");
    } else if (starts_with(input_buffer, "inb ")) {
        const char *arg = input_buffer + 4;
        unsigned int port = 0;
        if (arg[0] == '0' && (arg[1] == 'x' || arg[1] == 'X')) {
            for (const char *p = arg + 2; *p; p++) {
                char c = *p;
                port <<= 4;
                if (c >= '0' && c <= '9') port |= (c - '0');
                else if (c >= 'a' && c <= 'f') port |= (10 + c - 'a');
                else if (c >= 'A' && c <= 'F') port |= (10 + c - 'A');
                else break;
            }
        } else {
            for (const char *p = arg; *p; p++) {
                if (*p >= '0' && *p <= '9') port = port * 10 + (*p - '0');
                else break;
            }
        }
        uint8_t val = io_in8((uint16_t)port);
        char buf[8];
        const char hex[] = "0123456789ABCDEF";
        buf[0] = '0'; buf[1] = 'x'; buf[2] = hex[(val >> 4) & 0xF]; buf[3] = hex[val & 0xF]; buf[4] = '\0';
    log_print("\nINB -> ");
    log_print(buf);
    log_print("\n");
    } else if (strcmp(input_buffer, "ls") == 0 || starts_with(input_buffer, "ls ")) {
        /* list files from FAT root */
        fat_list_files();
    } else if (starts_with(input_buffer, "echo ")) {
        const char *arg = input_buffer + 5;
        log_print("\n");
        log_print(arg);
        log_print("\n");
    } else if (starts_with(input_buffer, "outb ")) {
        const char *arg = input_buffer + 5;
        unsigned int port = 0;
        unsigned int val = 0;
        int i = 0;
        while (arg[i] == ' ') i++;
        const char *p = arg + i;
        if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) {
            for (const char *q = p + 2; *q; q++) {
                char c = *q;
                port <<= 4;
                if (c >= '0' && c <= '9') port |= (c - '0');
                else if (c >= 'a' && c <= 'f') port |= (10 + c - 'a');
                else if (c >= 'A' && c <= 'F') port |= (10 + c - 'A');
                else break;
            }
        } else {
            for (const char *q = p; *q && *q != ' '; q++) {
                if (*q >= '0' && *q <= '9') port = port * 10 + (*q - '0');
                else break;
            }
        }
        const char *valtok = p;
        while (*valtok && *valtok != ' ') valtok++;
        while (*valtok == ' ') valtok++;
        if (valtok[0] == '0' && (valtok[1] == 'x' || valtok[1] == 'X')) {
            for (const char *q = valtok + 2; *q; q++) {
                char c = *q;
                val <<= 4;
                if (c >= '0' && c <= '9') val |= (c - '0');
                else if (c >= 'a' && c <= 'f') val |= (10 + c - 'a');
                else if (c >= 'A' && c <= 'F') val |= (10 + c - 'A');
                else break;
            }
        } else {
            for (const char *q = valtok; *q; q++) {
                if (*q >= '0' && *q <= '9') val = val * 10 + (*q - '0');
                else break;
            }
        }
        io_out8((uint16_t)port, (uint8_t)val);
    log_print("\nOUTB -> done\n");
    } else {
    log_print("\nUnknown command: ");
    log_print(input_buffer);
    log_print("\n");
    }

    shell_clear_input();
    shell_prompt();
}

void shell_input(char c) {
    if (c == '\n') {
        shell_execute();
    } else if (c == '\b') {
        if (input_length > 0) {
            input_length--;
            log_backspace();
        }
    } else {
        if (input_length < MAX_INPUT - 1) {
            input_buffer[input_length++] = c;
            log_put_char(c);
        }
    }
}

void shell_init() {
    log_print("YSH ready. Type 'help' for commands.\n");
    shell_prompt();
}

void shell_run() {
    while (true) {
        char c = keyboard_get_char();
        if (c) shell_input(c);
    }
}
