const vga = @import("vga/vga.zig");
const keyboard = @import("kb/keyboard.zig");
const shell = @import("shell.zig");
const multiboot = @import("multiboot.zig");
const fat = @import("fs/fat.zig");
const log = @import("log.zig");

pub fn init() void {
    const banner: [:0]const u8 = "YabaiOS Zig kernel\n";
    vga.vga_print(banner);
    keyboard.keyboard_init();
    log.print_message("Keyboard initialized\n");
    shell.shell_init();
}

pub fn run() noreturn {
    init();
    shell.shell_run();
}

pub export fn kernel_main(magic: u32, info_addr: u32) noreturn {
    _ = magic;
    const mbi: *const multiboot.MultibootInfo = @ptrFromInt(info_addr);

    // Initialize VGA first
    vga.vga_init();
    vga.vga_set_color(10, 0);
    log.print_message("Kernel starting\n");

    // Initialize framebuffer if available
    if ((mbi.flags & (1 << 12)) != 0 and mbi.framebuffer_addr != 0 and mbi.framebuffer_width > 0 and mbi.framebuffer_height > 0) {
        if (mbi.framebuffer_type == multiboot.MULTIBOOT_FRAMEBUFFER_TYPE_RGB and (mbi.framebuffer_bpp == 32 or mbi.framebuffer_bpp == 24)) {
            _ = vga.vga_use_framebuffer(
                mbi.framebuffer_addr,
                mbi.framebuffer_pitch,
                mbi.framebuffer_width,
                mbi.framebuffer_height,
                mbi.framebuffer_bpp,
                mbi.color_info, // red_position
                8, // red_mask_size, assuming
                8, // green
                8, // blue
                0, // blue_position
                8, // blue_mask_size
            );
            log.print_message("Framebuffer initialized\n");
        }
    }

    // Initialize FAT if module present
    log.print_message("Checking for modules\n");
    if ((mbi.flags & (1 << 3)) != 0 and mbi.mods_count > 0) {
        log.print_message("Modules found\n");
        const mods: [*]const multiboot.MultibootModule = @ptrFromInt(mbi.mods_addr);
        const disk_image = mods[0].mod_start;
        _ = fat.fat_init(disk_image);
    } else {
        log.print_message("No modules found\n");
    }

    run();
}
