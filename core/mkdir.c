// mkdir - make directory
#include "../kernel/kernel.h"

void _start() {
    struct program_args *args = program_args();

    if (!args || args->argc < 2) {
        kernel_api()->log_print("mkdir: missing operand\n");
        return;
    }

    const char *dirname = args->argv[1];
    
    if (kernel_api()->fat_create_dir) {
        int result = kernel_api()->fat_create_dir(dirname);
        if (result != 0) {
            kernel_api()->log_print("mkdir: cannot create directory '");
            kernel_api()->log_print(dirname);
            kernel_api()->log_print("'\n");
        }
    } else {
        kernel_api()->log_print("mkdir: fat_create_dir not available\n");
    }
}
