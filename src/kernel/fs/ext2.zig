const std = @import("std");

// ext2 superblock structure
const Ext2Superblock = extern struct {
    inode_count: u32,
    block_count: u32,
    reserved_blocks: u32,
    free_blocks: u32,
    free_inodes: u32,
    block_size_shift: u32, // block_size = 1024 << block_size_shift
    fragment_size_shift: u32,
    blocks_per_group: u32,
    fragments_per_group: u32,
    inodes_per_group: u32,
    mount_time: u32,
    write_time: u32,
    mount_count: u16,
    max_mount_count: u16,
    magic: u16, // 0xEF53
    fs_state: u16,
    error_behavior: u16,
    minor_version: u16,
    last_check: u32,
    check_interval: u32,
    os_id: u32,
    major_version: u32,
    uid_reserved: u16,
    gid_reserved: u16,
    first_inode: u32,
    inode_size: u16,
    block_group_number: u16,
    feature_compat: u32,
    feature_incompat: u32,
    feature_ro_compat: u32,
    uuid: [16]u8,
    volume_name: [16]u8,
    last_mounted: [64]u8,
    algorithm_usage_bitmap: u32,
    reserved: [205]u32,
};

// ext2 inode structure
const Ext2Inode = extern struct {
    mode: u16,
    uid: u16,
    size_low: u32,
    atime: u32,
    ctime: u32,
    mtime: u32,
    dtime: u32,
    gid: u16,
    link_count: u16,
    blocks: u32,
    flags: u32,
    osd1: u32,
    block: [15]u32,
    generation: u32,
    file_acl: u32,
    dir_acl_size_high: u32,
    fragment_addr: u32,
    osd2: [12]u8,
};

// ext2 directory entry
const Ext2DirEntry = extern struct {
    inode: u32,
    rec_len: u16,
    name_len: u8,
    file_type: u8,
    // name follows immediately, up to 255 bytes
};

var fs_image: ?[*]u8 = null;
var fs_image_size: usize = 0;
var superblock: ?*Ext2Superblock = null;
var block_size: u32 = 0;

pub export fn ext2_init(image: usize) bool {
    const base: [*]u8 = @ptrFromInt(image);
    fs_image = base;
    fs_image_size = 10 * 1024 * 1024; // assume 10MB

    const log = @import("../log.zig");
    log.print_message("ext2: Initializing filesystem\n");

    // Log the image base address and first few bytes
    var addr_buf: [64]u8 = [_]u8{0} ** 64;
    _ = std.fmt.bufPrintZ(&addr_buf, "Image base: 0x{X:0>8}\n", .{image}) catch return false;
    log.print_message(@as([*:0]const u8, @ptrCast(&addr_buf)));

    // Log first 16 bytes
    var first_bytes_buf: [128]u8 = [_]u8{0} ** 128;
    _ = std.fmt.bufPrintZ(&first_bytes_buf, "First bytes: {X:0>2} {X:0>2} {X:0>2} {X:0>2}\n", .{ base[0], base[1], base[2], base[3] }) catch return false;
    log.print_message(@as([*:0]const u8, @ptrCast(&first_bytes_buf)));

    // Superblock is at offset 1024
    const sb_ptr: *Ext2Superblock = @ptrCast(@alignCast(&base[1024]));

    // Log bytes at offset 1024
    var offset_buf: [128]u8 = [_]u8{0} ** 128;
    _ = std.fmt.bufPrintZ(&offset_buf, "Offset 1024: {X:0>2} {X:0>2} {X:0>2} {X:0>2}\n", .{ base[1024], base[1025], base[1026], base[1027] }) catch return false;
    log.print_message(@as([*:0]const u8, @ptrCast(&offset_buf)));

    const magic_val: u16 = sb_ptr.magic;
    var magic_buf: [64]u8 = [_]u8{0} ** 64;

    // Print magic value in hex
    _ = std.fmt.bufPrintZ(&magic_buf, "Magic: 0x{X:0>4}\n", .{magic_val}) catch return false;
    log.print_message(@as([*:0]const u8, @ptrCast(&magic_buf)));
    if (sb_ptr.magic != 0xEF53) {
        log.print_message("ext2: Invalid magic number\n");
        return false;
    }

    superblock = sb_ptr;
    block_size = @as(u32, 1024) << @as(u5, @intCast(sb_ptr.block_size_shift));

    log.print_message("ext2 Filesystem initialized\n");
    return true;
}

pub export fn ext2_list_root_directory() bool {
    if (superblock == null or fs_image == null) return false;

    const vga = @import("../vga/vga.zig");

    // Root inode is inode 2
    var inode_data: [1024]u8 = [_]u8{0} ** 1024;
    if (!ext2_read_inode(2, &inode_data)) {
        vga.vga_print("Failed to read root inode\n");
        return false;
    }

    const inode: *Ext2Inode = @ptrCast(@alignCast(&inode_data));

    // Read directory entries
    const dir_block = inode.block[0];
    if (dir_block == 0) {
        vga.vga_print("(empty)\n");
        return true;
    }

    const block_data = fs_image.?[(dir_block * block_size)..((dir_block + 1) * block_size)];
    var offset: usize = 0;
    var entry_count: usize = 0;

    while (offset < inode.size_low) {
        if (offset + 8 > block_data.len) break;

        const dir_entry: *const Ext2DirEntry = @ptrCast(@alignCast(&block_data[offset]));
        if (dir_entry.inode == 0) break;

        // Print filename
        const name_len = dir_entry.name_len;
        const name_offset = offset + @sizeOf(Ext2DirEntry);

        for (0..name_len) |i| {
            if (name_offset + i < block_data.len) {
                vga.vga_put_char(block_data[name_offset + i]);
            }
        }

        // Print if directory
        if (dir_entry.file_type == 2) { // directory
            vga.vga_print("/");
        }

        vga.vga_put_char('\n');
        entry_count += 1;

        offset += dir_entry.rec_len;
    }

    if (entry_count == 0) {
        vga.vga_print("(empty)\n");
    }

    return true;
}

pub export fn ext2_list_directory(dirname: [*:0]const u8) bool {
    if (superblock == null or fs_image == null) return false;

    const vga = @import("../vga/vga.zig");

    // Find inode for directory
    const inode_num = ext2_find_inode_in_dir(2, dirname) orelse {
        vga.vga_print("Directory not found\n");
        return false;
    };

    var inode_data: [1024]u8 = [_]u8{0} ** 1024;
    if (!ext2_read_inode(inode_num, &inode_data)) {
        vga.vga_print("Failed to read inode\n");
        return false;
    }

    const inode: *Ext2Inode = @ptrCast(@alignCast(&inode_data));
    const dir_block = inode.block[0];

    if (dir_block == 0) {
        vga.vga_print("(empty)\n");
        return true;
    }

    const block_data = fs_image.?[(dir_block * block_size)..((dir_block + 1) * block_size)];
    var offset: usize = 0;
    var entry_count: usize = 0;

    while (offset < inode.size_low) {
        if (offset + 8 > block_data.len) break;

        const dir_entry: *const Ext2DirEntry = @ptrCast(@alignCast(&block_data[offset]));
        if (dir_entry.inode == 0) break;

        const name_len = dir_entry.name_len;
        const name_offset = offset + @sizeOf(Ext2DirEntry);

        for (0..name_len) |i| {
            if (name_offset + i < block_data.len) {
                vga.vga_put_char(block_data[name_offset + i]);
            }
        }

        if (dir_entry.file_type == 2) {
            vga.vga_print("/");
        }

        vga.vga_put_char('\n');
        entry_count += 1;

        offset += dir_entry.rec_len;
    }

    if (entry_count == 0) {
        vga.vga_print("(empty)\n");
    }

    return true;
}

pub export fn ext2_read_file(filename: [*:0]const u8, buffer: [*]u8, size: *usize) bool {
    if (superblock == null or fs_image == null) return false;

    // Parse path
    var path_i: usize = 0;
    var parts: [10][256]u8 = [_][256]u8{[_]u8{0} ** 256} ** 10;
    var part_count: usize = 0;
    var current_part: [256]u8 = [_]u8{0} ** 256;
    var current_part_len: usize = 0;

    while (filename[path_i] != 0) : (path_i += 1) {
        const c = filename[path_i];
        if (c == '/') {
            if (current_part_len > 0) {
                std.mem.copyForwards(u8, &parts[part_count], &current_part);
                part_count += 1;
                current_part = [_]u8{0} ** 256;
                current_part_len = 0;
            }
        } else {
            current_part[current_part_len] = c;
            current_part_len += 1;
        }
    }
    if (current_part_len > 0) {
        std.mem.copyForwards(u8, &parts[part_count], &current_part);
        part_count += 1;
    }

    // Navigate directory tree
    var current_inode: u32 = 2; // root

    var i: usize = 0;
    while (i < part_count - 1) : (i += 1) {
        var part_cstr: [257]u8 = [_]u8{0} ** 257;
        var j: usize = 0;
        while (parts[i][j] != 0 and j < 256) : (j += 1) {
            part_cstr[j] = parts[i][j];
        }

        const next_inode = ext2_find_inode_in_dir(current_inode, @as([*:0]const u8, @ptrCast(&part_cstr))) orelse {
            return false;
        };
        current_inode = next_inode;
    }

    // Read file
    var filename_cstr: [257]u8 = [_]u8{0} ** 257;
    var k: usize = 0;
    while (parts[part_count - 1][k] != 0 and k < 256) : (k += 1) {
        filename_cstr[k] = parts[part_count - 1][k];
    }

    const file_inode_num = ext2_find_inode_in_dir(current_inode, @as([*:0]const u8, @ptrCast(&filename_cstr))) orelse {
        return false;
    };

    var inode_data: [1024]u8 = [_]u8{0} ** 1024;
    if (!ext2_read_inode(file_inode_num, &inode_data)) {
        return false;
    }

    const inode: *Ext2Inode = @ptrCast(@alignCast(&inode_data));
    const file_size = inode.size_low;

    if (file_size > 4096) {
        return false;
    }

    // Read file data
    const block = inode.block[0];
    const block_data = fs_image.?[(block * block_size)..((block + 1) * block_size)];
    std.mem.copyForwards(u8, buffer[0..file_size], block_data[0..file_size]);
    size.* = file_size;

    return true;
}

pub export fn ext2_show_info() void {
    if (superblock == null) return;

    const vga = @import("../vga/vga.zig");
    const sb = superblock.?;

    vga.vga_print("ext2 Filesystem Info:\n");
    vga.vga_print("  Block size: ");
    var val = block_size;
    var digits: [10]u8 = [_]u8{0} ** 10;
    var digit_count: usize = 0;
    while (val > 0) : (val /= 10) {
        digits[digit_count] = @as(u8, @intCast(48 + (val % 10)));
        digit_count += 1;
    }
    var i: usize = digit_count;
    while (i > 0) : (i -= 1) {
        vga.vga_put_char(digits[i - 1]);
    }
    vga.vga_put_char('\n');

    vga.vga_print("  Total inodes: ");
    val = sb.inode_count;
    digit_count = 0;
    while (val > 0) : (val /= 10) {
        digits[digit_count] = @as(u8, @intCast(48 + (val % 10)));
        digit_count += 1;
    }
    i = digit_count;
    while (i > 0) : (i -= 1) {
        vga.vga_put_char(digits[i - 1]);
    }
    vga.vga_put_char('\n');
}

fn ext2_read_inode(inode_num: u32, buffer: [*]u8) bool {
    if (superblock == null or fs_image == null) return false;
    const sb = superblock.?;

    const inode_size = sb.inode_size;
    const inode_per_group = sb.inodes_per_group;
    const block_group = (inode_num - 1) / inode_per_group;
    const inode_in_group = (inode_num - 1) % inode_per_group;

    // Block group descriptor table starts at block 2
    const gdt_block = 2;
    const block_group_desc_offset = gdt_block * block_size + block_group * 32;

    const gdt_data = fs_image.?[block_group_desc_offset .. block_group_desc_offset + 32];

    var inode_table_block: u32 = 0;
    inode_table_block |= @as(u32, gdt_data[8]);
    inode_table_block |= @as(u32, gdt_data[9]) << 8;
    inode_table_block |= @as(u32, gdt_data[10]) << 16;
    inode_table_block |= @as(u32, gdt_data[11]) << 24;

    const inode_offset = inode_table_block * block_size + inode_in_group * inode_size;

    if (inode_offset + inode_size > fs_image_size) {
        return false;
    }

    std.mem.copyForwards(u8, buffer[0..inode_size], fs_image.?[inode_offset .. inode_offset + inode_size]);
    return true;
}

fn ext2_find_inode_in_dir(dir_inode_num: u32, name: [*:0]const u8) ?u32 {
    if (superblock == null or fs_image == null) return null;

    var inode_data: [1024]u8 = [_]u8{0} ** 1024;
    if (!ext2_read_inode(dir_inode_num, &inode_data)) {
        return null;
    }

    const inode: *Ext2Inode = @ptrCast(@alignCast(&inode_data));
    const dir_block = inode.block[0];

    if (dir_block == 0) {
        return null;
    }

    const block_data = fs_image.?[(dir_block * block_size)..((dir_block + 1) * block_size)];
    var offset: usize = 0;

    while (offset < inode.size_low) {
        if (offset + 8 > block_data.len) break;

        const dir_entry: *const Ext2DirEntry = @ptrCast(@alignCast(&block_data[offset]));
        if (dir_entry.inode == 0) break;

        const name_len = dir_entry.name_len;
        const name_offset = offset + @sizeOf(Ext2DirEntry);

        // Compare names
        var match = true;
        var i: usize = 0;
        while (name[i] != 0 and i < name_len) : (i += 1) {
            if (name[i] != block_data[name_offset + i]) {
                match = false;
                break;
            }
        }

        if (match and name[i] == 0 and i == name_len) {
            return dir_entry.inode;
        }

        offset += dir_entry.rec_len;
    }

    return null;
}
