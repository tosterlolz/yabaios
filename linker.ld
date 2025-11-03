ENTRY(_start)

SECTIONS
{
    /* Multiboot-compatible entry at 1MB for bootloader compatibility */
    . = 1M;

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
