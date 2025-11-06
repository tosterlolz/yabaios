const std = @import("std");

const multiboot = @import("../multiboot.zig");

const FAT_BPB = extern struct {
    jmpBoot: [3]u8,
    OEMName: [8]u8,
    bytesPerSector: u16,
    sectorsPerCluster: u8,
    reservedSectors: u16,
    numFATs: u8,
    rootEntryCount: u16,
    totalSectors16: u16,
    mediaType: u8,
    sectorsPerFAT16: u16,
    sectorsPerTrack: u16,
    numHeads: u16,
    hiddenSectors: u32,
    totalSectors32: u32,
    // FAT32 fields
    sectorsPerFAT32: u32,
    flags: u16,
    version: u16,
    rootCluster: u32,
    fsInfoSector: u16,
    backupBootSector: u16,
    reserved: [12]u8,
    driveNumber: u8,
    reserved1: u8,
    bootSignature: u8,
    volumeID: u32,
    volumeLabel: [11]u8,
    fsType: [8]u8,
};

const FAT_DirEntry = extern struct {
    name: [11]u8,
    attr: u8,
    reserved: u8,
    createTimeFine: u8,
    createTime: u16,
    createDate: u16,
    accessDate: u16,
    clusterHigh: u16,
    modifiedTime: u16,
    modifiedDate: u16,
    clusterLow: u16,
    fileSize: u32,
};

var fat_image: ?[*]u8 = null;
var fat_image_size: usize = 0;
var bpb: ?*FAT_BPB = null;
var root_dir_offset: usize = 0;
var data_offset: usize = 0;
var root_entries: usize = 0;
var root_cluster: u32 = 0;
var bytes_per_sector: u16 = 0;
var sectors_per_cluster: u8 = 0;

pub export fn fat_init(image: usize) bool {
    const base: [*]u8 = @ptrFromInt(image);
    fat_image = base;
    fat_image_size = 10 * 1024 * 1024; // assume 10MB

    const log = @import("../log.zig");
    log.print_message("FAT: Initializing filesystem\n");

    // The image should start with the BPB directly (no boot signature offset needed for a module)
    const candidate: *FAT_BPB = @ptrCast(@alignCast(base));

    const bps = candidate.bytesPerSector;
    const spc = candidate.sectorsPerCluster;

    if (bps == 0 or spc == 0) {
        log.print_message("FAT: Invalid BPB (bps or spc is 0)\n");
        return false;
    }

    bpb = candidate;
    bytes_per_sector = candidate.bytesPerSector;
    sectors_per_cluster = candidate.sectorsPerCluster;
    root_cluster = candidate.rootCluster;

    const sectorsPerFAT = if (candidate.sectorsPerFAT16 == 0) candidate.sectorsPerFAT32 else candidate.sectorsPerFAT16;
    root_dir_offset = (candidate.reservedSectors + candidate.numFATs * sectorsPerFAT) * bps;

    // For FAT32, data_offset is calculated differently
    if (candidate.rootCluster > 0) {
        // FAT32: data area starts after FATs, root is in a cluster
        data_offset = (candidate.reservedSectors + candidate.numFATs * sectorsPerFAT) * bps;
        root_entries = (@as(usize, spc) * bps) / 32;
    } else {
        // FAT16: data_offset is after the fixed root directory
        data_offset = root_dir_offset + candidate.rootEntryCount * 32;
        root_entries = candidate.rootEntryCount;
    }

    log.print_message("FAT Filesystem initialized\n");
    var debug_buf: [64]u8 = [_]u8{0} ** 64;
    var debug_len: usize = 0;
    const fmt_str = "root_entries: ";
    for (fmt_str) |c| {
        if (debug_len < debug_buf.len) {
            debug_buf[debug_len] = c;
            debug_len += 1;
        }
    }
    var val = root_entries;
    var digits: [10]u8 = [_]u8{0} ** 10;
    var digit_count: usize = 0;
    while (val > 0) : (val /= 10) {
        digits[digit_count] = @as(u8, @intCast(48 + (val % 10)));
        digit_count += 1;
    }
    var i: usize = digit_count;
    while (i > 0) : (i -= 1) {
        if (debug_len < debug_buf.len) {
            debug_buf[debug_len] = digits[i - 1];
            debug_len += 1;
        }
    }
    if (debug_len < debug_buf.len) {
        debug_buf[debug_len] = '\n';
        debug_len += 1;
    }
    debug_buf[debug_len] = 0;
    log.print_message(@as([*:0]const u8, @ptrCast(&debug_buf)));
    return true;
}

fn fat_read_file_in_dir(dir11: *const [11]u8, filename11: *const [11]u8, buffer: [*]u8, size: *usize) bool {
    if (bpb == null or fat_image == null) return false;
    const b = bpb.?;

    // Find dir in root
    // For FAT32, root directory is at rootCluster
    const root_offset = if (root_cluster > 0)
        (root_cluster - 2) * @as(usize, bytes_per_sector) * @as(usize, sectors_per_cluster)
    else
        root_dir_offset;
    const root: [*]FAT_DirEntry = @ptrCast(@alignCast(&fat_image.?[root_offset]));
    var dir_cluster: u32 = 0;
    var i: usize = 0;

    // Search for directory in root
    while (i < root_entries) : (i += 1) {
        const entry = root[i];
        if (entry.name[0] == 0) break;
        if (entry.name[0] == 0xE5) continue;
        if ((entry.attr & 0x10) == 0) continue; // must be directory
        if (std.mem.eql(u8, &entry.name, dir11)) {
            dir_cluster = (@as(u32, entry.clusterHigh) << 16) | entry.clusterLow;
            break;
        }
    }

    if (dir_cluster < 2) return false;

    // Read directory entries from dir_cluster
    const cluster_size = @as(usize, b.sectorsPerCluster) * b.bytesPerSector;
    const dir_offset = data_offset + (dir_cluster - 2) * cluster_size;

    if (dir_cluster < 2) {
        const log = @import("../log.zig");
        log.print_message("FAT: Directory not found\n");
        return false;
    }

    const log = @import("../log.zig");
    log.print_message("FAT: Found directory, reading files\n");
    if (dir_offset >= fat_image_size) return false;

    const dir_entries: [*]FAT_DirEntry = @ptrCast(@alignCast(&fat_image.?[dir_offset]));
    const num_entries = cluster_size / 32;

    i = 0;
    while (i < num_entries) : (i += 1) {
        const entry = dir_entries[i];
        if (entry.name[0] == 0) break;
        if (entry.name[0] == 0xE5) continue;
        if ((entry.attr & 0x10) != 0) continue; // skip directories
        if (std.mem.eql(u8, &entry.name, filename11)) {
            // Found file
            const cluster = (@as(u32, entry.clusterHigh) << 16) | entry.clusterLow;
            if (cluster < 2) return false;
            const file_size = entry.fileSize;
            if (file_size > cluster_size) return false;
            const file_cluster_offset = data_offset + (cluster - 2) * cluster_size;
            if (file_cluster_offset + file_size > fat_image_size) return false;
            std.mem.copyForwards(u8, buffer[0..file_size], fat_image.?[file_cluster_offset .. file_cluster_offset + file_size]);
            size.* = file_size;
            return true;
        }
    }
    return false;
}

pub export fn fat_read_file(filename: [*:0]const u8, buffer: [*]u8, size: *usize) bool {
    if (bpb == null or fat_image == null) return false;

    const b = bpb.?;

    // Parse path: /dir/file or /file
    var dir11: [11]u8 = [_]u8{' '} ** 11;
    var file11: [11]u8 = [_]u8{' '} ** 11;
    var in_dir = false;
    var last_slash: usize = 0;
    var src_i: usize = 0;
    while (filename[src_i] != 0) : (src_i += 1) {
        if (filename[src_i] == '/') {
            last_slash = src_i;
        }
    }

    if (last_slash == 0) {
        // No slash or only leading slash - root file
        in_dir = false;
        src_i = if (filename[0] == '/') @as(usize, 1) else @as(usize, 0);
        var dest_i: usize = 0;
        while (filename[src_i] != 0) : (src_i += 1) {
            const c = filename[src_i];
            if (c == '.') {
                dest_i = 8;
            } else if (dest_i < 11) {
                file11[dest_i] = std.ascii.toUpper(c);
                dest_i += 1;
            }
        }
    } else {
        // Has directory
        in_dir = true;
        var start: usize = 0;
        if (filename[0] == '/') {
            start = 1;
        }
        var dest_i: usize = 0;
        src_i = start;
        // Parse directory name until the last slash
        while (src_i < last_slash) : (src_i += 1) {
            const c = filename[src_i];
            if (c != '/') {
                if (dest_i < 8) {
                    dir11[dest_i] = std.ascii.toUpper(c);
                    dest_i += 1;
                }
            }
        }
        // Parse filename after the last slash
        src_i = last_slash + 1;
        dest_i = 0;
        while (filename[src_i] != 0) : (src_i += 1) {
            const c = filename[src_i];
            if (c == '.') {
                dest_i = 8;
            } else if (dest_i < 11) {
                file11[dest_i] = std.ascii.toUpper(c);
                dest_i += 1;
            }
        }
    }

    if (in_dir) {
        return fat_read_file_in_dir(&dir11, &file11, buffer, size);
    } else {
        // Root file
        const root: [*]FAT_DirEntry = @ptrCast(@alignCast(&fat_image.?[root_dir_offset]));
        var i: usize = 0;
        while (i < root_entries) : (i += 1) {
            const entry = root[i];
            if (entry.name[0] == 0) break;
            if (entry.name[0] == 0xE5) continue;
            if (entry.attr & 0x08 != 0) continue; // volume
            if (std.mem.eql(u8, &entry.name, &file11)) {
                // Found, read the file
                const cluster = (@as(u32, entry.clusterHigh) << 16) | entry.clusterLow;
                if (cluster < 2) return false;
                const file_size = entry.fileSize;
                const cluster_size = @as(usize, b.sectorsPerCluster) * b.bytesPerSector;
                if (file_size > cluster_size) return false; // assume fits in one cluster
                const cluster_offset = data_offset + (cluster - 2) * cluster_size;
                std.mem.copyForwards(u8, buffer[0..file_size], fat_image.?[cluster_offset .. cluster_offset + file_size]);
                size.* = file_size;
                return true;
            }
        }
        return false;
    }
}

pub export fn fat_list_root_directory() bool {
    if (bpb == null or fat_image == null) return false;

    const vga = @import("../vga/vga.zig");

    // List root directory entries
    // For FAT32, root directory is at rootCluster and may span multiple clusters
    var file_count: usize = 0;
    if (root_cluster > 0) {
        // FAT32: follow cluster chain
        var cluster = root_cluster;
        const b = bpb.?;
        const fat_offset = b.reservedSectors * b.bytesPerSector;
        const fat: [*]u8 = @ptrCast(@alignCast(&fat_image.?[fat_offset]));
        while (cluster >= 2 and cluster < 0x0FFFFFF8) {
            const cluster_size = @as(usize, b.sectorsPerCluster) * b.bytesPerSector;
            const dir_offset = data_offset + (cluster - 2) * cluster_size;
            const dir_entries: [*]FAT_DirEntry = @ptrCast(@alignCast(&fat_image.?[dir_offset]));
            const num_entries = cluster_size / 32;
            var i: usize = 0;
            while (i < num_entries) : (i += 1) {
                const entry = dir_entries[i];
                if (entry.name[0] == 0) break;
                if (entry.name[0] == 0xE5) continue;
                if ((entry.attr & 0x08) != 0) continue; // skip volume labels
                // Print filename (handle 8.3 format)
                var j: usize = 0;
                while (j < 8 and entry.name[j] != ' ') : (j += 1) {
                    vga.vga_put_char(entry.name[j]);
                }
                if (entry.name[8] != ' ') {
                    vga.vga_put_char('.');
                    var k: usize = 8;
                    while (k < 11 and entry.name[k] != ' ') : (k += 1) {
                        vga.vga_put_char(entry.name[k]);
                    }
                }
                if ((entry.attr & 0x10) != 0) {
                    vga.vga_print("/");
                }
                vga.vga_put_char(' ');
                // Print file size
                var size = entry.fileSize;
                var digits: [10]u8 = [_]u8{0} ** 10;
                var digit_count: usize = 0;
                if (size == 0) {
                    digits[0] = '0';
                    digit_count = 1;
                } else {
                    while (size > 0) : (size /= 10) {
                        digits[digit_count] = @as(u8, @intCast(48 + (size % 10)));
                        digit_count += 1;
                    }
                }
                var d: usize = digit_count;
                while (d > 0) : (d -= 1) {
                    vga.vga_put_char(digits[d - 1]);
                }
                vga.vga_put_char('\n');
                file_count += 1;
            }
            // Get next cluster from FAT
            const fat_index = cluster * 4;
            cluster = @as(u32, fat[fat_index]) | (@as(u32, fat[fat_index + 1]) << 8) | (@as(u32, fat[fat_index + 2]) << 16) | (@as(u32, fat[fat_index + 3]) << 24);
            cluster &= 0x0FFFFFFF;
        }
    } else {
        // FAT16: fixed root directory
        const root: [*]FAT_DirEntry = @ptrCast(@alignCast(&fat_image.?[root_dir_offset]));
        var i: usize = 0;
        while (i < root_entries) : (i += 1) {
            const entry = root[i];
            if (entry.name[0] == 0) break;
            if (entry.name[0] == 0xE5) continue;
            if ((entry.attr & 0x08) != 0) continue; // skip volume labels
            // Print filename (handle 8.3 format)
            var j: usize = 0;
            while (j < 8 and entry.name[j] != ' ') : (j += 1) {
                vga.vga_put_char(entry.name[j]);
            }
            if (entry.name[8] != ' ') {
                vga.vga_put_char('.');
                var k: usize = 8;
                while (k < 11 and entry.name[k] != ' ') : (k += 1) {
                    vga.vga_put_char(entry.name[k]);
                }
            }
            if ((entry.attr & 0x10) != 0) {
                vga.vga_print("/");
            }
            vga.vga_put_char(' ');
            // Print file size
            var size = entry.fileSize;
            var digits: [10]u8 = [_]u8{0} ** 10;
            var digit_count: usize = 0;
            if (size == 0) {
                digits[0] = '0';
                digit_count = 1;
            } else {
                while (size > 0) : (size /= 10) {
                    digits[digit_count] = @as(u8, @intCast(48 + (size % 10)));
                    digit_count += 1;
                }
            }
            var d: usize = digit_count;
            while (d > 0) : (d -= 1) {
                vga.vga_put_char(digits[d - 1]);
            }
            vga.vga_put_char('\n');
            file_count += 1;
        }
    }
    if (file_count == 0) {
        vga.vga_print("(empty)\n");
    }
    return true;
}

pub export fn fat_list_directory(dirname: [*:0]const u8) bool {
    if (bpb == null or fat_image == null) return false;

    const vga = @import("../vga/vga.zig");
    const b = bpb.?;

    // Convert dirname to 8.3 format (pad to 11 bytes with spaces)
    var dir11: [11]u8 = [_]u8{' '} ** 11;
    var src_i: usize = 0;
    var dest_i: usize = 0;

    while (dirname[src_i] != 0) : (src_i += 1) {
        const c = dirname[src_i];
        if (c == '.') {
            dest_i = 8;
        } else if (c != '/' and dest_i < 11) {
            dir11[dest_i] = std.ascii.toUpper(c);
            dest_i += 1;
        }
    }

    // Find directory in root
    // For FAT32, root directory is at rootCluster
    const root_offset = if (root_cluster > 0)
        (root_cluster - 2) * @as(usize, bytes_per_sector) * @as(usize, sectors_per_cluster)
    else
        root_dir_offset;
    const root: [*]FAT_DirEntry = @ptrCast(@alignCast(&fat_image.?[root_offset]));
    var dir_cluster: u32 = 0;
    var i: usize = 0;

    // Debug: print what we're looking for
    vga.vga_print("Looking for: ");
    for (0..11) |j| {
        if (dir11[j] != ' ') {
            vga.vga_put_char(dir11[j]);
        }
    }
    vga.vga_put_char('\n');

    // Search for directory in root
    while (i < root_entries) : (i += 1) {
        const entry = root[i];
        if (entry.name[0] == 0) break;
        if (entry.name[0] == 0xE5) continue;
        if ((entry.attr & 0x10) == 0) continue; // must be directory

        // Debug: print what we find
        vga.vga_print("Found: ");
        for (0..8) |j| {
            if (entry.name[j] != ' ') {
                vga.vga_put_char(entry.name[j]);
            }
        }
        vga.vga_put_char('\n');

        if (std.mem.eql(u8, &entry.name, &dir11)) {
            dir_cluster = (@as(u32, entry.clusterHigh) << 16) | entry.clusterLow;
            break;
        }
    }

    if (dir_cluster < 2) {
        vga.vga_print("Directory not found\n");
        return false;
    }

    // List directory entries from dir_cluster
    const cluster_size = @as(usize, b.sectorsPerCluster) * b.bytesPerSector;
    const dir_offset = data_offset + (dir_cluster - 2) * cluster_size;

    if (dir_offset >= fat_image_size) return false;

    const dir_entries: [*]FAT_DirEntry = @ptrCast(@alignCast(&fat_image.?[dir_offset]));
    const num_entries = cluster_size / 32;

    var file_count: usize = 0;
    i = 0;
    while (i < num_entries) : (i += 1) {
        const entry = dir_entries[i];
        if (entry.name[0] == 0) break;
        if (entry.name[0] == 0xE5) continue;
        if ((entry.attr & 0x08) != 0) continue; // skip volume labels

        // Print filename (handle 8.3 format)
        var j: usize = 0;
        while (j < 8 and entry.name[j] != ' ') : (j += 1) {
            vga.vga_put_char(entry.name[j]);
        }
        if (entry.name[8] != ' ') {
            vga.vga_put_char('.');
            var k: usize = 8;
            while (k < 11 and entry.name[k] != ' ') : (k += 1) {
                vga.vga_put_char(entry.name[k]);
            }
        }
        vga.vga_put_char(' ');

        // Print file size
        var size = entry.fileSize;
        var digits: [10]u8 = [_]u8{0} ** 10;
        var digit_count: usize = 0;
        if (size == 0) {
            digits[0] = '0';
            digit_count = 1;
        } else {
            while (size > 0) : (size /= 10) {
                digits[digit_count] = @as(u8, @intCast(48 + (size % 10)));
                digit_count += 1;
            }
        }
        var d: usize = digit_count;
        while (d > 0) : (d -= 1) {
            vga.vga_put_char(digits[d - 1]);
        }
        vga.vga_put_char('\n');
        file_count += 1;
    }

    if (file_count == 0) {
        vga.vga_print("(empty)\n");
    }

    return true;
}

pub export fn fat_debug_root() void {
    if (bpb == null or fat_image == null) return;

    const vga = @import("../vga/vga.zig");
    const root: [*]FAT_DirEntry = @ptrCast(@alignCast(&fat_image.?[root_dir_offset]));

    vga.vga_print("Root directory entries:\n");
    var i: usize = 0;
    while (i < root_entries) : (i += 1) {
        const entry = root[i];
        if (entry.name[0] == 0) {
            vga.vga_print("(end of directory)\n");
            break;
        }
        if (entry.name[0] == 0xE5) continue;

        // Print name
        for (0..11) |j| {
            vga.vga_put_char(entry.name[j]);
        }
        vga.vga_put_char(' ');

        // Print attribute
        vga.vga_put_char('[');
        var attr_str: [6]u8 = [_]u8{ '-', '-', '-', '-', '-', 0 };
        if ((entry.attr & 0x01) != 0) attr_str[0] = 'R';
        if ((entry.attr & 0x02) != 0) attr_str[1] = 'H';
        if ((entry.attr & 0x04) != 0) attr_str[2] = 'S';
        if ((entry.attr & 0x08) != 0) attr_str[3] = 'V';
        if ((entry.attr & 0x10) != 0) attr_str[4] = 'D';
        vga.vga_print(@as([*:0]const u8, @ptrCast(&attr_str)));
        vga.vga_print("]\n");
    }
}

pub export fn fat_show_info() void {
    if (bpb == null) return;

    const vga = @import("../vga/vga.zig");
    const b = bpb.?;

    vga.vga_print("FAT Filesystem Info:\n");

    // Print bytes per sector
    vga.vga_print("  Bytes/sector: ");
    var val: u32 = b.bytesPerSector;
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

    // Print sectors per cluster
    vga.vga_print("  Sectors/cluster: ");
    val = b.sectorsPerCluster;
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

    // Print root entries
    vga.vga_print("  Root entries: ");
    val = b.rootEntryCount;
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

    // Print sectors per FAT
    vga.vga_print("  Sectors/FAT: ");
    val = if (b.sectorsPerFAT16 == 0) b.sectorsPerFAT32 else @as(u32, b.sectorsPerFAT16);
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

pub export fn fat_open(filename: [*:0]const u8) ?[*]u8 {
    // Stub: return null for now
    _ = filename;
    return null;
}

pub export fn fat_read(file: [*]u8, buffer: [*]u8, size: usize) usize {
    // Stub: copy from file to buffer
    _ = file;
    _ = buffer;
    return size;
}
