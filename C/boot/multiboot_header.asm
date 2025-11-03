section .multiboot
align 4
    dd 0x1BADB002              ; magic number (Multiboot)
    dd 0x00                    ; flags
    dd -(0x1BADB002 + 0x00)    ; checksum

section .text
global _start
extern kernel_main

_start:
    push ebx               ; push multiboot info pointer
    push eax               ; push multiboot magic
    call kernel_main
    add esp, 8
    cli
    hlt
