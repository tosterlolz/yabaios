// pwd - print working directory
#include "../kernel/kernel.h"

void _start() {
    const char *cwd = kernel_api()->get_cwd();
    kernel_api()->log_print(cwd);
    kernel_api()->log_print("\n");
}
