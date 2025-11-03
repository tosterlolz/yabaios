// cd - change directory
#include "../kernel/kernel.h"

void _start() {
    struct program_args *args = program_args();

    if (!args || args->argc < 2) {
        kernel_api()->log_print("usage: cd <path>\n");
        return;
    }

    const char *path = args->argv[1];

    if (kernel_api()->set_cwd(path) == 0) {
        kernel_api()->log_print("cd: changed to ");
        kernel_api()->log_print(path);
        kernel_api()->log_print("\n");
    } else {
        kernel_api()->log_print("cd: failed to change directory\n");
    }
}
