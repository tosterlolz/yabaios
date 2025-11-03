// cp - copy file
#include "../kernel/kernel.h"

void _start() {
    struct program_args *args = program_args();

    if (!args || args->argc < 3) {
        kernel_api()->log_print("cp: missing operand\n");
        return;
    }

    const char *src = args->argv[1];
    const char *dst = args->argv[2];
    
    if (kernel_api()->fat_copy_file) {
        int result = kernel_api()->fat_copy_file(src, dst);
        if (result != 0) {
            kernel_api()->log_print("cp: cannot copy '");
            kernel_api()->log_print(src);
            kernel_api()->log_print("' to '");
            kernel_api()->log_print(dst);
            kernel_api()->log_print("'\n");
        }
    } else {
        kernel_api()->log_print("cp: fat_copy_file not available\n");
    }
}
