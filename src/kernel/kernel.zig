const vga = @import("vga/vga.zig");
const keyboard = @import("kb/keyboard.zig");
const shell = @import("shell.zig");
const ext2 = @import("fs/ext2.zig");
const log = @import("log.zig");
const idt = @import("idt.zig");

pub fn init() void {
    const banner: [:0]const u8 = "YabaiOS Zig kernel (64-bit)\n";
    vga.vga_print(banner);
    keyboard.keyboard_init();
    log.print_message("Keyboard initialized\n");
    shell.shell_init();
}

pub fn run() noreturn {
    init();
    shell.shell_run();
}

pub export fn kernel_main() noreturn {
    // First thing: try to write debug output directly to VGA
    // This is the absolute first thing that should happen
    var vga_ptr: [*]volatile u16 = @ptrFromInt(0xB8000);
    vga_ptr[15] = (0x0F << 8) | 'K'; // K in green
    vga_ptr[16] = (0x0F << 8) | 'Z'; // Z in green (for Zig kernel)

    // Initialize VGA first
    vga.vga_init();
    vga_ptr[17] = (0x0F << 8) | 'I'; // I after vga_init

    vga.vga_set_color(10, 0);
    log.print_message("Kernel started (64-bit)!\n");
    vga_ptr[18] = (0x0F << 8) | '1'; // 1 after first print

    keyboard.keyboard_init();
    log.print_message("Keyboard initialized\n");
    vga_ptr[19] = (0x0F << 8) | '2'; // 2 after keyboard

    // Set up interrupt handling
    idt.setup_pic();
    log.print_message("PIC initialized\n");
    vga_ptr[20] = (0x0F << 8) | '3'; // 3 after PIC

    idt.setup_idt();
    log.print_message("IDT initialized\n");
    vga_ptr[21] = (0x0F << 8) | '4'; // 4 after IDT

    idt.enable_interrupts();
    log.print_message("Interrupts enabled\n");
    vga_ptr[22] = (0x0F << 8) | '5'; // 5 after interrupts

    shell.shell_init();
    log.print_message("Shell initialized\n");
    vga_ptr[23] = (0x0F << 8) | '6'; // 6 after shell init

    // Try to load ext2 filesystem (for now, just print a message)
    log.print_message("Ext2 filesystem support compiled in\n");
    vga_ptr[24] = (0x0F << 8) | '7'; // 7 after ext2

    run();
}
