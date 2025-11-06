bits 16
section .multiboot_header
align 8

multiboot_header:
    dd 0xe85250d6              ; magic
    dd 0                       ; i386
    dd multiboot_header_end - multiboot_header
    dd -(0xe85250d6 + 0 + (multiboot_header_end - multiboot_header))
    
    dw 0                       ; End tag
    dw 0
    dd 8
multiboot_header_end:

bits 32
section .text
global _start
extern kernel_main

_start:
    cli
    cld
    
    ; DEBUG: Write '1' to VGA
    mov eax, 0xB8000
    mov byte [eax], '1'
    mov byte [eax + 1], 0x0F
    
    ; Save multiboot info
    mov [multiboot_magic], eax
    mov [multiboot_info], ebx
    
    ; DEBUG: Write '2'
    mov eax, 0xB8002
    mov byte [eax], '2'
    mov byte [eax + 1], 0x0F
    
    ; Set up stack
    mov esp, 0x100000
    
    ; DEBUG: Write '3'
    mov eax, 0xB8004
    mov byte [eax], '3'
    mov byte [eax + 1], 0x0F
    
    ; Call kernel_main directly (32-bit)
    push dword [multiboot_info]
    push dword [multiboot_magic]
    call kernel_main
    
    ; DEBUG: Write 'X' if we somehow return
    mov eax, 0xB8006
    mov byte [eax], 'X'
    mov byte [eax + 1], 0x0F
    
    cli
    hlt

section .data
multiboot_magic: dd 0
multiboot_info: dd 0
