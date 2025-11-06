// Custom bootloader for YabaiOS
// This runs in real mode and transitions to long mode

pub export fn bootloader_main() noreturn {
    vga_clear();
    vga_print("YabaiOS Bootloader\n");

    // Enable A20 line
    enable_a20();

    // Load kernel
    vga_print("Loading kernel...\n");

    // TODO: Load kernel from disk/media

    // Set up GDT for long mode
    setup_gdt();
    vga_print("GDT loaded\n");

    // Set up paging
    setup_paging();
    vga_print("Paging configured\n");

    // Switch to long mode
    enter_long_mode();

    // Should not reach here
    vga_print("ERROR: Failed to enter long mode\n");
    hang();
}

fn vga_clear() void {
    const vga_buffer = @as([*]volatile u16, @ptrFromInt(0xb8000));
    for (0..80 * 25) |i| {
        vga_buffer[i] = 0x0f20; // Black background, white text, space character
    }
}

fn vga_print(str: [*:0]const u8) void {
    const vga_buffer = @as([*]volatile u16, @ptrFromInt(0xb8000));
    var cursor: usize = 0;

    var i: usize = 0;
    while (str[i] != 0) : (i += 1) {
        const c = str[i];
        if (c == '\n') {
            cursor += (80 - (cursor % 80));
        } else {
            vga_buffer[cursor] = 0x0f00 | c;
            cursor += 1;
        }
        if (cursor >= 80 * 25) {
            cursor = 0;
        }
    }
}

fn enable_a20() void {
    // Simple A20 enable via BIOS
    // In real bootloader, would need more robust method
}

fn setup_gdt() void {
    // Set up Global Descriptor Table for long mode
    // This is simplified - real implementation needed
}

fn setup_paging() void {
    // Set up 4-level page tables for 64-bit paging
    // Map kernel to high addresses
}

fn enter_long_mode() void {
    // Enable CR0.PE (protected mode)
    // Load GDT
    // Set up CR3 with page directory
    // Enable PAE in CR4
    // Set IA32_EFER.LME (long mode enable)
    // Enable CR0.PG (paging)
    // Far jump to 64-bit code
}

fn hang() noreturn {
    while (true) {
        asm volatile ("cli; hlt");
    }
}
