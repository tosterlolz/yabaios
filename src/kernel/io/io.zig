pub fn in8(port: u16) u8 {
    var value: u8 = 0;
    asm volatile ("inb %dx, %al"
        : [out] "={al}" (value),
        : [port] "{dx}" (port),
    );
    return value;
}

pub fn out8(port: u16, value: u8) void {
    asm volatile ("outb %al, %dx"
        :
        : [port] "{dx}" (port),
          [value] "{al}" (value),
    );
}
