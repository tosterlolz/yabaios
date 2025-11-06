ENTRY(_start)

PHDRS
{
    text PT_LOAD FLAGS(5);    /* R + X */
    data PT_LOAD FLAGS(6);    /* W + R */
}

SECTIONS
{
    /* Multiboot2 standard load address: 1MB */
    . = 0x100000;

    .multiboot_header : {
        *(.multiboot_header)
    } :text

    .text : {
        *(.text*)
    } :text

    .rodata : { *(.rodata*) } :text
    
    .data : { *(.data*) } :data
    .bss : {
        *(COMMON)
        *(.bss*)
    } :data
}
