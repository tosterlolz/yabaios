pub const KernelApi = struct {
    print: *const fn ([*:0]const u8) void,
    put_char: *const fn (u8) void,
    clear: *const fn () void,
    backspace: *const fn () void,
    set_color: *const fn (u8, u8) void,
};
