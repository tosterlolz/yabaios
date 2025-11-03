#include "shell.h"
#include "log.h"
#include "../kb/keyboard.h"
#include "string.h"
#include "io.h"
#include "../fs/fat.h"
#include "elf.h"
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

    // Execution-only shell: attempt to execute the first token as a core ELF.
    // Build 8.3 name from token and try FAT, falling back to embedded initramfs.
    // Extract command token (first word)
    char cmdtoken[32];
    int ci = 0;
    while (ci < 31 && input_buffer[ci] && input_buffer[ci] != ' ') {
        cmdtoken[ci] = input_buffer[ci];
        ci++;
    }
    cmdtoken[ci] = '\0';

    if (ci > 0) {
        uint8_t name11[11];
        fat_format_83_name(cmdtoken, name11);

        static uint8_t elf_buf[64 * 1024];
        uint32_t elf_size = 0;
        if (fat_read_file((const char *)name11, elf_buf, &elf_size)) {
            // find args (rest of the input)
            const char *args = input_buffer + ci;
            while (*args == ' ') args++;
            elf_run_from_memory(elf_buf, elf_size, args);
        } else {
            // try /core/<name>
            uint8_t dir11[11];
            fat_format_83_name("core", dir11);
            if (fat_read_file_in_dir((const char *)dir11, (const char *)name11, elf_buf, &elf_size)) {
                const char *args = input_buffer + ci;
                while (*args == ' ') args++;
                elf_run_from_memory(elf_buf, elf_size, args);
            } else {
                log_print("\nUnknown command\n");
            }
        }
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
