bits 16
section .multiboot_header
align 8

multiboot_header:
    dd 0xe85250d6              ; magic
    dd 3                       ; architecture (3 for x86_64 / ia32e)
    dd multiboot_header_end - multiboot_header
    ; checksum = -(magic + architecture + header_length)
    dd -(0xe85250d6 + 3 + (multiboot_header_end - multiboot_header))
    
    ; End tag (multiboot2 tags are u32 type, u32 size)
    dd 0                       ; type = 0 (end)
    dd 8                       ; size = 8
multiboot_header_end:

; Switch to 64-bit code for kernel entry stub
bits 64
section .text
global _start
extern kernel_main

_start:
    cli
    cld

    ; DEBUG: Write '1' to VGA (64-bit form)
    mov rax, 0xB8000
    mov byte [rax], '1'
    mov byte [rax + 1], 0x0F

    ; Note: multiboot info fields are present for compatibility but not used here

    ; Set up stack (64-bit stack pointer)
    mov rsp, 0x0010_0000

    ; DEBUG: Write '3'
    mov rax, 0xB8004
    mov byte [rax], '3'
    mov byte [rax + 1], 0x0F

    ; Call kernel_main directly (64-bit)
    call kernel_main

    ; If kernel returns, show 'X'
    mov rax, 0xB8006
    mov byte [rax], 'X'
    mov byte [rax + 1], 0x0F

    cli
    hlt

section .data
multiboot_magic: dd 0
multiboot_info: dd 0
