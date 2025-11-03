// edit - simple text file editor stub
#include "../kernel/kernel.h"

void _start() {
    struct program_args *args = program_args();

    if (!args || args->argc < 2) {
        kernel_api()->log_print("usage: edit <filename>\n");
        return;
    }

    const char *filename = args->argv[1];
    kernel_api()->log_print("edit: opening file: ");
    kernel_api()->log_print(filename);
    kernel_api()->log_print("\n");

    /* For now, just show the file contents */
    uint8_t buffer[4096];
    uint32_t size = sizeof(buffer);

    if (!kernel_api()->fat_read_file(filename, buffer, &size)) {
        kernel_api()->log_print("Current contents:\n");
        for (uint32_t i = 0; i < size; i++) {
            kernel_api()->log_put_char((char)buffer[i]);
        }
        kernel_api()->log_print("\n");
    } else {
        kernel_api()->log_print("(new file)\n");
    }

    kernel_api()->log_print("edit: not fully implemented (read-only mode)\n");
}

