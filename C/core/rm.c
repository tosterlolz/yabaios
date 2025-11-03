// rm - remove file
#include "../kernel/kernel.h"

void _start() {
    struct program_args *args = program_args();

    if (!args || args->argc < 2) {
        kernel_api()->log_print("rm: missing operand\n");
        return;
    }

    const char *filename = args->argv[1];
    
    if (kernel_api()->fat_delete_file) {
        int result = kernel_api()->fat_delete_file(filename);
        if (result != 0) {
            kernel_api()->log_print("rm: cannot remove '");
            kernel_api()->log_print(filename);
            kernel_api()->log_print("'\n");
        }
    } else {
        kernel_api()->log_print("rm: fat_delete_file not available\n");
    }
}
