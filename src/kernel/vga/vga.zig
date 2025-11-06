const font = @import("font8x8_basic.zig");

const VGA_WIDTH: usize = 80;
const VGA_HEIGHT: usize = 25;
const FB_CHAR_WIDTH: usize = 8;
const FB_CHAR_HEIGHT: usize = 16;

fn vgaMemory() [*]volatile u16 {
    return @ptrFromInt(@as(usize, 0xB8000));
}

var cursor_row: usize = 0;
var cursor_col: usize = 0;
var current_fg: u8 = 7;
var current_bg: u8 = 0;
var color: u8 = 0x0F;

var fb_enabled: bool = false;
var fb_base_addr: usize = 0;
var fb_pitch: u32 = 0;
var fb_width: u32 = 0;
var fb_height: u32 = 0;
var fb_bytes_per_pixel: u32 = 0;
var fb_cols: usize = 0;
var fb_rows: usize = 0;
var fb_red_position: u8 = 16;
var fb_red_mask_size: u8 = 8;
var fb_green_position: u8 = 8;
var fb_green_mask_size: u8 = 8;
var fb_blue_position: u8 = 0;
var fb_blue_mask_size: u8 = 8;
var fb_fore_color: u32 = 0x00FFFFFF;
var fb_back_color: u32 = 0x00000000;

const palette = [_][3]u8{
    .{ 0x00, 0x00, 0x00 }, .{ 0x00, 0x00, 0xAA }, .{ 0x00, 0xAA, 0x00 }, .{ 0x00, 0xAA, 0xAA },
    .{ 0xAA, 0x00, 0x00 }, .{ 0xAA, 0x00, 0xAA }, .{ 0xAA, 0x55, 0x00 }, .{ 0xAA, 0xAA, 0xAA },
    .{ 0x55, 0x55, 0x55 }, .{ 0x55, 0x55, 0xFF }, .{ 0x55, 0xFF, 0x55 }, .{ 0x55, 0xFF, 0xFF },
    .{ 0xFF, 0x55, 0x55 }, .{ 0xFF, 0x55, 0xFF }, .{ 0xFF, 0xFF, 0x55 }, .{ 0xFF, 0xFF, 0xFF },
};

fn getFbBase() [*]u8 {
    return @ptrFromInt(fb_base_addr);
}

fn vgaEntryColor(fg: u8, bg: u8) u8 {
    return (fg & 0x0F) | ((bg & 0x0F) << 4);
}

fn vgaEntry(uc: u8, color_value: u8) u16 {
    return @as(u16, uc) | (@as(u16, color_value) << 8);
}

fn scaleComponent(value: u8, mask_size: u8) u32 {
    if (mask_size == 0 or mask_size >= 32) return 0;
    const shift: u5 = @intCast(mask_size);
    const max_value: u32 = (@as(u32, 1) << shift) - 1;
    return (@as(u32, value) * max_value + 127) / 255;
}

fn fbPackColor(r: u8, g: u8, b: u8) u32 {
    var value: u32 = 0;
    if (fb_red_mask_size != 0) {
        const red_width: u6 = @intCast(fb_red_mask_size);
        const red_width_shift: u5 = @intCast(red_width);
        const red_mask: u32 = (@as(u32, 1) << red_width_shift) - 1;
        const red = scaleComponent(r, fb_red_mask_size) & red_mask;
        const red_pos: u6 = @intCast(fb_red_position);
        const red_shift: u5 = @intCast(red_pos);
        value |= red << red_shift;
    }
    if (fb_green_mask_size != 0) {
        const green_width: u6 = @intCast(fb_green_mask_size);
        const green_width_shift: u5 = @intCast(green_width);
        const green_mask: u32 = (@as(u32, 1) << green_width_shift) - 1;
        const green = scaleComponent(g, fb_green_mask_size) & green_mask;
        const green_pos: u6 = @intCast(fb_green_position);
        const green_shift: u5 = @intCast(green_pos);
        value |= green << green_shift;
    }
    if (fb_blue_mask_size != 0) {
        const blue_width: u6 = @intCast(fb_blue_mask_size);
        const blue_width_shift: u5 = @intCast(blue_width);
        const blue_mask: u32 = (@as(u32, 1) << blue_width_shift) - 1;
        const blue = scaleComponent(b, fb_blue_mask_size) & blue_mask;
        const blue_pos: u6 = @intCast(fb_blue_position);
        const blue_shift: u5 = @intCast(blue_pos);
        value |= blue << blue_shift;
    }
    return value;
}

fn fbPackIndex(index: u8) u32 {
    const idx: usize = @intCast(index & 0x0F);
    const rgb = palette[idx];
    return fbPackColor(rgb[0], rgb[1], rgb[2]);
}

fn fbUpdateDimensions() void {
    if (fb_width == 0 or fb_height == 0) {
        fb_cols = 1;
        fb_rows = 1;
        return;
    }
    const width_usize: usize = @intCast(fb_width);
    const height_usize: usize = @intCast(fb_height);
    fb_cols = width_usize / FB_CHAR_WIDTH;
    if (fb_cols == 0) fb_cols = 1;
    fb_rows = height_usize / FB_CHAR_HEIGHT;
    if (fb_rows == 0) fb_rows = 1;
}

fn fbUpdatePalette() void {
    fb_fore_color = fbPackIndex(current_fg);
    fb_back_color = fbPackIndex(current_bg);
}

fn fbDrawChar(ch: u8, row: usize, col: usize) void {
    if (!fb_enabled or fb_base_addr == 0) return;
    if (row >= fb_rows or col >= fb_cols) return;

    const glyph_index: usize = @intCast(ch & 0x7F);
    const pitch_usize: usize = @intCast(fb_pitch);
    const bytes_per_pixel_usize: usize = @intCast(fb_bytes_per_pixel);
    const base = getFbBase();
    const x0: usize = col * FB_CHAR_WIDTH;
    const y0: usize = row * FB_CHAR_HEIGHT;

    var y: usize = 0;
    while (y < FB_CHAR_HEIGHT) : (y += 1) {
        const glyph = font.font8x8_basic[glyph_index][(y >> 1) & 0x07];
        const row_ptr = base + (y0 + y) * pitch_usize;
        const row_addr = @intFromPtr(row_ptr);
        const dst_addr = row_addr + x0 * bytes_per_pixel_usize;
        const dst: [*]u32 = @ptrFromInt(dst_addr);

        var x: usize = 0;
        while (x < FB_CHAR_WIDTH) : (x += 1) {
            const shift: u3 = @intCast(x);
            const mask: u8 = (@as(u8, 0x80) >> shift);
            dst[x] = if ((glyph & mask) != 0) fb_fore_color else fb_back_color;
        }
    }
}

fn fbScroll() void {
    if (!fb_enabled or fb_base_addr == 0) return;
    if (fb_rows <= 1) return;

    const pitch_usize: usize = @intCast(fb_pitch);
    const bytes_per_pixel_usize: usize = @intCast(fb_bytes_per_pixel);
    const base = getFbBase();
    const char_height = FB_CHAR_HEIGHT;
    const active_height = fb_rows * FB_CHAR_HEIGHT;
    if (active_height <= char_height) return;

    const bytes_per_char_row = pitch_usize * char_height;
    const bytes_to_copy = pitch_usize * (active_height - char_height);

    var i: usize = 0;
    while (i < bytes_to_copy) : (i += 1) {
        base[i] = base[i + bytes_per_char_row];
    }

    var y: usize = 0;
    while (y < char_height) : (y += 1) {
        const row_ptr = base + bytes_to_copy + y * pitch_usize;
        var x: usize = 0;
        const width_usize: usize = @intCast(fb_width);
        while (x < width_usize) : (x += 1) {
            const pixel_addr = @intFromPtr(row_ptr) + x * bytes_per_pixel_usize;
            const pixel_ptr: *u32 = @ptrFromInt(pixel_addr);
            pixel_ptr.* = fb_back_color;
        }
    }

    if (fb_rows > 0) {
        cursor_row = fb_rows - 1;
        cursor_col = 0;
    }
}

fn fbNewline() void {
    cursor_col = 0;
    cursor_row += 1;
    if (cursor_row >= fb_rows) {
        fbScroll();
    }
}

fn fbPutPrintable(ch: u8) void {
    var printable = ch;
    if (ch < 0x20 and ch != 0x20) printable = '?';

    fbDrawChar(printable, cursor_row, cursor_col);
    cursor_col += 1;
    if (cursor_col >= fb_cols) {
        fbNewline();
    }
}

fn textmodeScroll() void {
    const mem = vgaMemory();
    var y: usize = 0;
    while (y + 1 < VGA_HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < VGA_WIDTH) : (x += 1) {
            mem[y * VGA_WIDTH + x] = mem[(y + 1) * VGA_WIDTH + x];
        }
    }
    var x: usize = 0;
    while (x < VGA_WIDTH) : (x += 1) {
        mem[(VGA_HEIGHT - 1) * VGA_WIDTH + x] = vgaEntry(' ', color);
        x += 1;
    }
    cursor_row = VGA_HEIGHT - 1;
    cursor_col = 0;
}

pub export fn vga_set_color(fg: u8, bg: u8) void {
    current_fg = fg & 0x0F;
    current_bg = bg & 0x0F;
    color = vgaEntryColor(current_fg, current_bg);
    if (fb_enabled) {
        fbUpdatePalette();
    }
}

pub export fn vga_init() void {
    fb_enabled = false;
    fb_base_addr = 0;
    fb_pitch = 0;
    fb_width = 0;
    fb_height = 0;
    fb_bytes_per_pixel = 0;
    fb_cols = 0;
    fb_rows = 0;
    cursor_row = 0;
    cursor_col = 0;
    current_fg = 7;
    current_bg = 0;
    color = vgaEntryColor(current_fg, current_bg);
    vga_clear();
}

pub export fn vga_clear() void {
    cursor_row = 0;
    cursor_col = 0;

    if (fb_enabled and fb_base_addr != 0) {
        const base = getFbBase();
        const pitch_usize: usize = @intCast(fb_pitch);
        const width_usize: usize = @intCast(fb_width);
        const active_height = fb_rows * FB_CHAR_HEIGHT;

        var y: usize = 0;
        while (y < active_height) : (y += 1) {
            const row_ptr = base + y * pitch_usize;
            var x: usize = 0;
            const bpp_usize: usize = @intCast(fb_bytes_per_pixel);
            while (x < width_usize) : (x += 1) {
                const pixel_addr = @intFromPtr(row_ptr) + x * bpp_usize;
                const pixel_ptr: *u32 = @ptrFromInt(pixel_addr);
                pixel_ptr.* = fb_back_color;
            }
        }
        return;
    }

    const mem = vgaMemory();
    var y: usize = 0;
    while (y < VGA_HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < VGA_WIDTH) : (x += 1) {
            mem[y * VGA_WIDTH + x] = vgaEntry(' ', color);
        }
    }
}

pub export fn vga_put_char(ch: u8) void {
    if (fb_enabled and fb_base_addr != 0) {
        switch (ch) {
            '\n' => {
                fbNewline();
                return;
            },
            '\r' => {
                cursor_col = 0;
                return;
            },
            '\t' => {
                const spaces = 4 - (cursor_col % 4);
                var i: usize = 0;
                while (i < spaces) : (i += 1) {
                    fbPutPrintable(' ');
                }
                return;
            },
            else => {},
        }
        fbPutPrintable(ch);
        return;
    }

    switch (ch) {
        '\n' => {
            cursor_col = 0;
            cursor_row += 1;
            if (cursor_row >= VGA_HEIGHT) {
                textmodeScroll();
            }
            return;
        },
        '\r' => {
            cursor_col = 0;
            return;
        },
        '\t' => {
            const spaces = 4 - (cursor_col % 4);
            var i: usize = 0;
            while (i < spaces) : (i += 1) {
                vga_put_char(' ');
            }
            return;
        },
        else => {},
    }

    const mem = vgaMemory();
    mem[cursor_row * VGA_WIDTH + cursor_col] = vgaEntry(ch, color);
    cursor_col += 1;
    if (cursor_col >= VGA_WIDTH) {
        cursor_col = 0;
        cursor_row += 1;
        if (cursor_row >= VGA_HEIGHT) {
            textmodeScroll();
        }
    }
}

pub export fn vga_print(str: [*:0]const u8) void {
    var i: usize = 0;
    while (str[i] != 0) : (i += 1) {
        vga_put_char(str[i]);
    }
}

pub export fn vga_backspace() void {
    if (fb_enabled and fb_base_addr != 0) {
        if (cursor_col > 0) {
            cursor_col -= 1;
        } else if (cursor_row > 0) {
            cursor_row -= 1;
            cursor_col = if (fb_cols > 0) fb_cols - 1 else 0;
        } else {
            return;
        }
        fbDrawChar(' ', cursor_row, cursor_col);
        return;
    }

    const mem = vgaMemory();
    if (cursor_col > 0) {
        cursor_col -= 1;
    } else if (cursor_row > 0) {
        cursor_row -= 1;
        cursor_col = VGA_WIDTH - 1;
    } else {
        return;
    }
    mem[cursor_row * VGA_WIDTH + cursor_col] = vgaEntry(' ', color);
}

pub export fn vga_use_framebuffer(
    addr: u64,
    pitch: u32,
    width: u32,
    height: u32,
    bpp: u8,
    red_position: u8,
    red_mask_size: u8,
    green_position: u8,
    green_mask_size: u8,
    blue_position: u8,
    blue_mask_size: u8,
) bool {
    if (addr == 0 or pitch == 0 or width == 0 or height == 0) return false;
    if (bpp != 32) return false;

    fb_base_addr = @intCast(addr);
    fb_pitch = pitch;
    fb_width = width;
    fb_height = height;
    fb_bytes_per_pixel = bpp / 8;
    if (fb_bytes_per_pixel == 0) return false;

    fb_red_position = red_position;
    fb_red_mask_size = red_mask_size;
    fb_green_position = green_position;
    fb_green_mask_size = green_mask_size;
    fb_blue_position = blue_position;
    fb_blue_mask_size = blue_mask_size;

    fb_enabled = true;
    fbUpdateDimensions();
    fbUpdatePalette();
    cursor_row = 0;
    cursor_col = 0;
    vga_clear();
    return true;
}
