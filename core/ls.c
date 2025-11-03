// simple freestanding ls program for YabaiOS core (demo)
#include "kernel.h"

void _start() {
    kernel_api()->log_print("core ls:\n  echo  cat  touch  edit\n");
    for (;;) __asm__("hlt");
}
