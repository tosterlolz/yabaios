section .multiboot
align 4
    dd 0x1BADB002              ; magic number (Multiboot)
    dd 0x00                    ; flags
    dd -(0x1BADB002 + 0x00)    ; checksum

section .text
global _start
extern kernel_main

_start:
    call kernel_main
    cli
    hlt
