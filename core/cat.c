// cat stub using kernel API
#include "kernel.h"

void _start() {
    kernel_api()->log_print("core cat: not implemented\n");
    for (;;) __asm__("hlt");
}
