.code16
.section .text
.global _start

_start:
    /* Real mode entry point - bootloader starts here */
    cli
    
    /* Initialize segments */
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    
    /* Set up stack */
    mov sp, 0x7c00
    
    /* Print a character to show we're booting */
    mov al, 'B'
    call print_char
    
    /* Call Zig bootloader */
    call bootloader_main
    
    /* Hang if we return */
    cli
    hlt

print_char:
    /* Print character in AL to screen using BIOS */
    mov ah, 0x0e
    int 0x10
    ret

/* Align to 512 bytes for boot sector */
.align 512
