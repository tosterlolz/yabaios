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
    
    xor eax, eax
    xor ebx, ebx
    xor ecx, ecx
    xor edx, edx
    xor esi, esi
    xor edi, edi
    xor ebp, ebp
    
    mov esp, 0x7000
    
    jmp startup_64bit

align 16
startup_64bit:
    ; Clear page tables
    mov eax, 0x1000
    xor ecx, ecx
clear_tables:
    mov dword [eax], 0
    add eax, 4
    cmp eax, 0x4000
    jl clear_tables
    
    ; Set up PML4
    mov eax, 0x2003
    mov dword [0x1000], eax
    mov dword [0x1000 + 0x1f8], eax
    
    ; Set up PDPT
    mov eax, 0x3003
    mov dword [0x2000], eax
    mov dword [0x2000 + 0x1f8], eax
    
    ; Set up PD - map first 2MB
    mov eax, 0x83
    mov dword [0x3000], eax
    mov dword [0x3000 + 0x1f8], eax
    
    ; Set CR3 to PML4
    mov eax, 0x1000
    mov cr3, eax
    
    ; Enable PAE in CR4
    mov eax, cr4
    or eax, 0x20
    mov cr4, eax
    
    ; Enable long mode in EFER MSR
    mov ecx, 0xc0000080
    rdmsr
    or eax, 0x100
    wrmsr
    
    ; Enable paging in CR0
    mov eax, cr0
    or eax, 0x80000001
    mov cr0, eax
    
    ; Load GDT and jump to 64-bit code
    lgdt [gdtr]
    jmp 0x08:kernel_entry_64bit

align 16
gdt:
    dq 0                       ; Null descriptor
    dq 0x00209A0000000000      ; Code descriptor (64-bit)
    dq 0x0000920000000000      ; Data descriptor

gdtr:
    dw 24
    dd gdt

bits 64
kernel_entry_64bit:
    mov rsp, 0x7000
    
    mov rax, kernel_main
    call rax
    
    cli
    hlt
