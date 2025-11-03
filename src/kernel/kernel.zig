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
    // Initialize VGA first
    vga.vga_init();
    vga.vga_set_color(10, 0);
    log.print_message("Kernel started (64-bit)!\n");

    keyboard.keyboard_init();
    log.print_message("Keyboard initialized\n");

    // Set up interrupt handling
    idt.setup_pic();
    log.print_message("PIC initialized\n");

    idt.setup_idt();
    log.print_message("IDT initialized\n");

    idt.enable_interrupts();
    log.print_message("Interrupts enabled\n");

    shell.shell_init();
    log.print_message("Shell initialized\n");

    // Try to load ext2 filesystem (for now, just print a message)
    log.print_message("Ext2 filesystem support compiled in\n");

    run();
}
