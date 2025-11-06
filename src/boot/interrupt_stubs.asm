bits 64
section .text

; Generic interrupt handler stub
; Calls the keyboard_interrupt_handler from idt.zig
extern keyboard_interrupt_handler

global interrupt_21_stub
interrupt_21_stub:
    ; Save registers
    push rax
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11
    
    ; Call the handler
    call keyboard_interrupt_handler
    
    ; Restore registers
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rax
    
    ; Return from interrupt
    iretq
