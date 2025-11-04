ENTRY(_start)

SECTIONS
{
    /* Multiboot2 standard load address: 1MB */
    . = 0x100000;

    .multiboot_header : {
        *(.multiboot_header)
    }

    .text : {
        *(.text*)
    }

    .rodata : { *(.rodata*) }
    .data : { *(.data*) }
    .bss : {
        *(COMMON)
        *(.bss*)
    }
}
