ENTRY(_start)

SECTIONS
{
    /* Multiboot-compatible entry at 0x20000 for floppy loader */
    . = 0x20000;

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
