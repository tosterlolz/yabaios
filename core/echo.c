// echo program using kernel API
#include "kernel.h"

void _start() {
    const char *args;
    __asm__("movl %%ebx, %0" : "=r"(args));
    kernel_api()->log_print(args);
    for (;;) __asm__("hlt");
}
