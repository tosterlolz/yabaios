// echo program using kernel API
#include "../kernel/kernel.h"

void _start() {
    struct program_args *args = program_args();

    if (!args || args->argc <= 1) {
        kernel_api()->log_print("\n");
        return;
    }

    /* Print all arguments separated by spaces */
    for (int i = 1; i < args->argc; i++) {
        if (i > 1) {
            kernel_api()->log_put_char(' ');
        }
        kernel_api()->log_print(args->argv[i]);
    }
    kernel_api()->log_print("\n");
}

