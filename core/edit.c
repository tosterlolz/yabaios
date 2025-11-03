// simple edit stub using kernel API
#include "kernel.h"

void _start() {
    kernel_api()->log_print("core edit: ok\n");
    for (;;) __asm__("hlt");
}
