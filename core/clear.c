// clear - clear the screen
#include "../kernel/kernel.h"

void _start() {
    struct program_args *args = program_args();
    (void)args;  /* Mark as intentionally unused */

    kernel_api()->log_clear();
}
