// cat - concatenate and display files
#include "../kernel/kernel.h"

void _start() {
    struct program_args *args = program_args();

    if (!args || args->argc < 2) {
        kernel_api()->log_print("usage: cat <filename>\n");
        return;
    }

    /* Read and print each file argument */
    for (int i = 1; i < args->argc; i++) {
        uint8_t buffer[4096];
        uint32_t size = sizeof(buffer);

        if (kernel_api()->fat_read_file(args->argv[i], buffer, &size)) {
            kernel_api()->log_print("cat: cannot open ");
            kernel_api()->log_print(args->argv[i]);
            kernel_api()->log_print("\n");
            continue;
        }

        /* Print file contents */
        for (uint32_t j = 0; j < size; j++) {
            kernel_api()->log_put_char((char)buffer[j]);
        }
    }
}

