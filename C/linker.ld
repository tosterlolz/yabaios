ENTRY(_start)

SECTIONS
{
    . = 1M; /* kernel starts at 1MB */

    .text : {
        *(.multiboot)
        *(.text*)
    }

    .rodata : { *(.rodata*) }
    .data : { *(.data*) }
    .bss : {
        *(COMMON)
        *(.bss*)
    }
}
