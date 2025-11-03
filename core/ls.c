// ls - list directory contents
#include "../kernel/kernel.h"

void _start() {
    struct program_args *args = program_args();

    if (!args || args->argc < 1) {
        kernel_api()->log_print("ls\n");
        return;
    }

    /* Parse options (reserved for future use) */
    (void)args;  /* Mark as intentionally unused if no options */

    /* List files */
    if (kernel_api()->fat_list_files) {
        kernel_api()->fat_list_files();
    } else {
        kernel_api()->log_print("ls: fat_list_files not available\n");
    }
}

