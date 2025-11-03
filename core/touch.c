// touch - create empty files
#include "../kernel/kernel.h"

void _start() {
    struct program_args *args = program_args();

    if (!args || args->argc < 2) {
        kernel_api()->log_print("usage: touch <filename>\n");
        return;
    }

    /* Create each file argument */
    for (int i = 1; i < args->argc; i++) {
        if (kernel_api()->fat_write_file(args->argv[i], "", 0)) {
            kernel_api()->log_print("touch: failed to create ");
            kernel_api()->log_print(args->argv[i]);
            kernel_api()->log_print("\n");
        } else {
            kernel_api()->log_print("touch: created ");
            kernel_api()->log_print(args->argv[i]);
            kernel_api()->log_print("\n");
        }
    }
}

