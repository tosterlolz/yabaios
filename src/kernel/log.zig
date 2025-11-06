const vga = @import("vga/vga.zig");

pub fn print_message(msg: [*:0]const u8) void {
    vga.vga_print("[LOG] ");
    vga.vga_print(msg);
}
