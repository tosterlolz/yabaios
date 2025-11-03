const Api = struct {
    print: *const fn ([*:0]const u8) void,
    put_char: *const fn (u8) void,
    clear: *const fn () void,
    backspace: *const fn () void,
    set_color: *const fn (u8, u8) void,
};

export fn _start(api: *const Api) void {
    api.print("Test program executed successfully!\n");
}
