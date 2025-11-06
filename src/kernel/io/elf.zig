const api = @import("../api.zig");
const vga = @import("../vga/vga.zig");

const EXEC_AREA_SIZE = 1024 * 1024;
var exec_area: [EXEC_AREA_SIZE]u8 = [_]u8{0} ** EXEC_AREA_SIZE;

const Elf32_Ehdr = extern struct {
    e_ident: [16]u8,
    e_type: u16,
    e_machine: u16,
    e_version: u32,
    e_entry: u32,
    e_phoff: u32,
    e_shoff: u32,
    e_flags: u32,
    e_ehsize: u16,
    e_phentsize: u16,
    e_phnum: u16,
    e_shentsize: u16,
    e_shnum: u16,
    e_shstrndx: u16,
};

const Elf32_Phdr = extern struct {
    p_type: u32,
    p_offset: u32,
    p_vaddr: u32,
    p_paddr: u32,
    p_filesz: u32,
    p_memsz: u32,
    p_flags: u32,
    p_align: u32,
};

const PT_LOAD = 1;

pub export fn elf_load(image: [*]u8, size: usize) bool {
    if (size < @sizeOf(Elf32_Ehdr)) return false;
    const eh = @as(*align(1) const Elf32_Ehdr, @ptrCast(image));
    if (eh.e_ident[0] != 0x7F or eh.e_ident[1] != 'E' or eh.e_ident[2] != 'L' or eh.e_ident[3] != 'F') return false;

    const ph_start = @as([*]align(1) const Elf32_Phdr, @ptrCast(@as([*]u8, image) + eh.e_phoff));
    const base = @intFromPtr(&exec_area[0]);
    var i: usize = 0;
    while (i < eh.e_phnum) : (i += 1) {
        const ph = &ph_start[i];
        if (ph.p_type != PT_LOAD) continue;
        if (ph.p_offset + ph.p_filesz > size) return false;
        if (ph.p_memsz > EXEC_AREA_SIZE) return false;
        const dst = @as([*]u8, @ptrFromInt(base));
        const src = @as([*]u8, @ptrCast(image + ph.p_offset));
        for (0..ph.p_filesz) |k| {
            dst[k] = src[k];
        }
        for (ph.p_filesz..ph.p_memsz) |k| {
            dst[k] = 0;
        }
    }

    const entry = @as(*const fn (*const api.KernelApi) void, @ptrFromInt(base + eh.e_entry));

    const kernel_api = api.KernelApi{
        .print = @ptrCast(&vga.vga_print),
        .put_char = @ptrCast(&vga.vga_put_char),
        .clear = @ptrCast(&vga.vga_clear),
        .backspace = @ptrCast(&vga.vga_backspace),
        .set_color = @ptrCast(&vga.vga_set_color),
    };

    entry(&kernel_api);
    return true;
}
