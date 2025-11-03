bits 16
org 0x7c00

; El Torito bootable image
; This is loaded by the BIOS and needs to bootstrap into 64-bit mode

section .text
global _start

_start:
    cli
    
    ; Set up real mode segments
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7c00
    
    ; Print "Booting..." using BIOS
    mov si, boot_msg
    call print_string
    
    ; Load kernel from disk
    ; For now, we'll just jump to the kernel at 1MB
    ; In a real bootloader, we'd read from disk
    
    ; Enable A20 line
    call enable_a20
    
    ; Switch to protected mode first, then long mode
    ; Load GDT
    lgdt [gdt_pointer]
    
    ; Enable PE bit in CR0
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    
    ; Jump to 32-bit code
    jmp 0x08:protected_mode

bits 32
protected_mode:
    ; Set up data segments
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    
    ; Set up stack
    mov esp, 0x7000
    
    ; Now set up long mode
    ; Enable PAE
    mov eax, cr4
    or eax, 0x20
    mov cr4, eax
    
    ; Set up page tables (identity map first 2MB)
    mov eax, 0x1000
    xor ecx, ecx
clear_tables:
    mov dword [eax], 0
    add eax, 4
    cmp eax, 0x4000
    jl clear_tables
    
    ; PML4
    mov eax, 0x2003
    mov dword [0x1000], eax
    
    ; PDPT
    mov eax, 0x3003
    mov dword [0x2000], eax
    
    ; PD with 2MB pages
    mov eax, 0x83
    mov dword [0x3000], eax
    
    ; Load CR3
    mov eax, 0x1000
    mov cr3, eax
    
    ; Enable long mode in EFER MSR
    mov ecx, 0xc0000080
    rdmsr
    or eax, 0x100
    wrmsr
    
    ; Enable paging
    mov eax, cr0
    or eax, 0x80000001
    mov cr0, eax
    
    ; Jump to 64-bit code
    jmp 0x08:0x100000

; 16-bit functions
bits 16
enable_a20:
    ; Simple A20 enable using keyboard controller
    mov al, 0xd1
    out 0x64, al
    mov al, 0xdf
    out 0x60, al
    ret

print_string:
    lodsb
    test al, al
    jz .done
    mov ah, 0x0e
    int 0x10
    jmp print_string
.done:
    ret

boot_msg: db "YabaiOS Boot", 0

; GDT
align 8
gdt:
    dq 0                       ; Null descriptor
    dq 0x00209A0000000000      ; Code descriptor
    dq 0x0000920000000000      ; Data descriptor

gdt_pointer:
    dw 24
    dd gdt

; Padding to 512 bytes
times 510-($-$$) db 0
db 0x55, 0xaa  ; Boot signature
