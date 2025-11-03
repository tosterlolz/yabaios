// simple touch stub using kernel API
#include "kernel.h"

void _start() {
    kernel_api()->log_print("core touch: ok\n");
    for (;;) __asm__("hlt");
}
