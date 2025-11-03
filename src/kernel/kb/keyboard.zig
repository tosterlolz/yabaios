const io = @import("../io/io.zig");

const PORT_DATA: u16 = 0x60;
const PORT_STATUS: u16 = 0x64;
const KB_BUFFER_SIZE: usize = 64;

fn buildKeymap() [128]u8 {
    var map = [_]u8{0} ** 128;
    map[0x01] = 27;
    map[0x02] = '1';
    map[0x03] = '2';
    map[0x04] = '3';
    map[0x05] = '4';
    map[0x06] = '5';
    map[0x07] = '6';
    map[0x08] = '7';
    map[0x09] = '8';
    map[0x0A] = '9';
    map[0x0B] = '0';
    map[0x0C] = '-';
    map[0x0D] = '=';
    map[0x0E] = '\x08';
    map[0x0F] = '\x09';
    map[0x10] = 'q';
    map[0x11] = 'w';
    map[0x12] = 'e';
    map[0x13] = 'r';
    map[0x14] = 't';
    map[0x15] = 'y';
    map[0x16] = 'u';
    map[0x17] = 'i';
    map[0x18] = 'o';
    map[0x19] = 'p';
    map[0x1A] = '[';
    map[0x1B] = ']';
    map[0x1C] = '\n';
    map[0x1E] = 'a';
    map[0x1F] = 's';
    map[0x20] = 'd';
    map[0x21] = 'f';
    map[0x22] = 'g';
    map[0x23] = 'h';
    map[0x24] = 'j';
    map[0x25] = 'k';
    map[0x26] = 'l';
    map[0x27] = ';';
    map[0x28] = '\'';
    map[0x29] = '`';
    map[0x2B] = '\\';
    map[0x2C] = 'z';
    map[0x2D] = 'x';
    map[0x2E] = 'c';
    map[0x2F] = 'v';
    map[0x30] = 'b';
    map[0x31] = 'n';
    map[0x32] = 'm';
    map[0x33] = ',';
    map[0x34] = '.';
    map[0x35] = '/';
    map[0x37] = '*';
    map[0x39] = ' ';
    return map;
}

fn buildShiftKeymap() [128]u8 {
    var map = [_]u8{0} ** 128;
    map[0x01] = 27;
    map[0x02] = '!';
    map[0x03] = '@';
    map[0x04] = '#';
    map[0x05] = '$';
    map[0x06] = '%';
    map[0x07] = '^';
    map[0x08] = '&';
    map[0x09] = '*';
    map[0x0A] = '(';
    map[0x0B] = ')';
    map[0x0C] = '_';
    map[0x0D] = '+';
    map[0x0E] = '\x08';
    map[0x0F] = '\x09';
    map[0x1A] = '{';
    map[0x1B] = '}';
    map[0x27] = ':';
    map[0x28] = '"';
    map[0x29] = '~';
    map[0x2B] = '|';
    map[0x33] = '<';
    map[0x34] = '>';
    map[0x35] = '?';
    map[0x37] = '*';
    map[0x39] = ' ';
    return map;
}

const keymap = buildKeymap();
const keymap_shift = buildShiftKeymap();

var key_buffer: [KB_BUFFER_SIZE]u8 = [_]u8{0} ** KB_BUFFER_SIZE;
var buffer_head: usize = 0;
var buffer_tail: usize = 0;
var left_shift: bool = false;
var right_shift: bool = false;
var caps_lock: bool = false;
var extended_code: bool = false;

fn bufferEmpty() bool {
    return buffer_head == buffer_tail;
}

fn bufferPush(ch: u8) void {
    const next = (buffer_head + 1) % KB_BUFFER_SIZE;
    if (next != buffer_tail) {
        key_buffer[buffer_head] = ch;
        buffer_head = next;
    }
}

fn bufferPop() u8 {
    if (bufferEmpty()) return 0;
    const ch = key_buffer[buffer_tail];
    buffer_tail = (buffer_tail + 1) % KB_BUFFER_SIZE;
    return ch;
}

pub fn processScancode(scancode: u8) void {
    if (scancode == 0xE0) {
        extended_code = true;
        return;
    }

    const release = (scancode & 0x80) != 0;
    const code: u8 = scancode & 0x7F;

    if (extended_code) {
        extended_code = false;
        return;
    }

    switch (code) {
        0x2A => {
            left_shift = !release;
            return;
        },
        0x36 => {
            right_shift = !release;
            return;
        },
        0x3A => {
            if (!release) caps_lock = !caps_lock;
            return;
        },
        else => {},
    }

    if (release or code >= keymap.len) return;

    const base = keymap[code];
    if (base == 0) return;

    const shift_active = left_shift or right_shift;
    var ch = base;

    if (shift_active and keymap_shift[code] != 0) {
        ch = keymap_shift[code];
    }

    if (base >= 'a' and base <= 'z') {
        var uppercase = caps_lock;
        if (shift_active) uppercase = !uppercase;
        if (uppercase) {
            ch = base - ('a' - 'A');
        } else {
            ch = base;
        }
    }

    bufferPush(ch);
}

pub export fn keyboard_init() void {
    buffer_head = 0;
    buffer_tail = 0;
    left_shift = false;
    right_shift = false;
    caps_lock = false;
    extended_code = false;
}

pub export fn keyboard_handle_input() void {
    while ((io.in8(PORT_STATUS) & 0x01) != 0) {
        const scancode = io.in8(PORT_DATA);
        processScancode(scancode);
    }
}

pub export fn keyboard_get_char() u8 {
    keyboard_handle_input();
    return bufferPop();
}

pub export fn keyboard_interrupt_handler() void {
    // Read scancode from keyboard port
    const scancode = io.in8(PORT_DATA);

    // Process the scancode
    processScancode(scancode);

    // Signal EOI to PIC
    io.out8(0x20, 0x20);
}
