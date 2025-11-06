// Interrupt handling for x86_64
const std = @import("std");

pub const IDT_SIZE = 256;

pub const InterruptFrame = extern struct {
    rip: u64,
    cs: u64,
    rflags: u64,
    rsp: u64,
    ss: u64,
};

pub const IDTEntry = extern struct {
    offset_low: u16,
    selector: u16,
    ist: u8,
    flags: u8,
    offset_mid: u16,
    offset_high: u32,
    reserved: u32,

    fn encode(handler: u64, selector: u16, flags: u8) IDTEntry {
        return IDTEntry{
            .offset_low = @intCast(handler & 0xFFFF),
            .selector = selector,
            .ist = 0,
            .flags = flags,
            .offset_mid = @intCast((handler >> 16) & 0xFFFF),
            .offset_high = @intCast((handler >> 32) & 0xFFFFFFFF),
            .reserved = 0,
        };
    }
};

pub const IDTPointer = extern struct {
    limit: u16,
    base: u64,
};

var idt: [IDT_SIZE]IDTEntry = undefined;

extern fn interrupt_21_stub() void;
extern fn keyboard_interrupt_handler() void;

pub fn setup_idt() void {
    // Initialize all entries to zero
    for (0..IDT_SIZE) |i| {
        idt[i] = std.mem.zeroes(IDTEntry);
    }

    // Set up keyboard interrupt (IRQ1 = INT 0x21)
    // 0x8E = present, ring 0, 64-bit interrupt gate
    idt[0x21] = IDTEntry.encode(@intFromPtr(&interrupt_21_stub), 0x08, 0x8E);

    // Load IDT
    const idt_ptr = IDTPointer{
        .limit = (@as(u16, IDT_SIZE) * @sizeOf(IDTEntry)) - 1,
        .base = @intFromPtr(&idt[0]),
    };

    asm volatile ("lidt %[ptr]"
        :
        : [ptr] "m" (idt_ptr),
    );
}

pub fn setup_pic() void {
    // Initialize PIC (Programmable Interrupt Controller)
    // ICW1
    @import("io/io.zig").out8(0x20, 0x11);
    @import("io/io.zig").out8(0xA0, 0x11);

    // ICW2 - Set base interrupt vectors
    @import("io/io.zig").out8(0x21, 0x20); // Master PIC: interrupts start at 0x20
    @import("io/io.zig").out8(0xA1, 0x28); // Slave PIC: interrupts start at 0x28

    // ICW3
    @import("io/io.zig").out8(0x21, 0x04);
    @import("io/io.zig").out8(0xA1, 0x02);

    // ICW4
    @import("io/io.zig").out8(0x21, 0x01);
    @import("io/io.zig").out8(0xA1, 0x01);

    // Unmask keyboard interrupt (IRQ1)
    var mask = @import("io/io.zig").in8(0x21);
    mask &= ~@as(u8, 0x02); // Clear bit 1 for IRQ1
    @import("io/io.zig").out8(0x21, mask);
}

pub fn enable_interrupts() void {
    asm volatile ("sti");
}

pub fn disable_interrupts() void {
    asm volatile ("cli");
}
