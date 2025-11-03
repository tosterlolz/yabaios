const std = @import("std");
const vga = @import("vga/vga.zig");
const keyboard = @import("kb/keyboard.zig");
const ext2 = @import("fs/ext2.zig");
const elf = @import("io/elf.zig");

const SHELL_BUFFER_SIZE: usize = 256;

var shell_buffer: [SHELL_BUFFER_SIZE]u8 = [_]u8{0} ** SHELL_BUFFER_SIZE;
var buffer_index: usize = 0;

// Current working directory
var current_dir: [256]u8 = [_]u8{0} ** 256;
var current_dir_len: usize = 0;

pub fn shell_get_cwd() [*:0]const u8 {
    if (current_dir_len == 0) {
        // Default to /bin
        current_dir[0] = '/';
        current_dir_len = 1;
    }
    return @as([*:0]const u8, @ptrCast(&current_dir));
}

pub fn shell_init() void {
    vga.vga_print("YabaiOS Shell\n");
}

pub fn shell_run() noreturn {
    while (true) {
        shell_prompt();
        shell_read_line();
        shell_execute();
    }
}

fn shell_prompt() void {
    vga.vga_print("YabaiOS:");
    const cwd = shell_get_cwd();
    var i: usize = 0;
    while (cwd[i] != 0) : (i += 1) {
        vga.vga_put_char(cwd[i]);
    }
    vga.vga_print("$ ");
}

fn shell_read_line() void {
    buffer_index = 0;
    while (buffer_index < SHELL_BUFFER_SIZE - 1) {
        const ch = keyboard.keyboard_get_char();
        if (ch == 0) continue;
        if (ch == '\n') {
            shell_buffer[buffer_index] = 0;
            vga.vga_put_char('\n');
            return;
        } else if (ch == '\x08') { // backspace
            if (buffer_index > 0) {
                buffer_index -= 1;
                vga.vga_backspace();
            }
        } else {
            shell_buffer[buffer_index] = ch;
            buffer_index += 1;
            vga.vga_put_char(ch);
        }
    }
    shell_buffer[buffer_index] = 0;
    vga.vga_put_char('\n');
}

fn shell_execute() void {
    if (buffer_index == 0) return;

    const command = shell_buffer[0..buffer_index];

    const MAX_ARGS = 10;
    var args: [MAX_ARGS][]const u8 = undefined;
    var arg_count: usize = 0;

    var start: usize = 0;
    var i: usize = 0;
    while (i < command.len) : (i += 1) {
        if (command[i] == ' ') {
            if (start < i) {
                if (arg_count < MAX_ARGS) {
                    args[arg_count] = command[start..i];
                    arg_count += 1;
                }
            }
            start = i + 1;
        }
    }
    if (start < command.len) {
        if (arg_count < MAX_ARGS) {
            args[arg_count] = command[start..];
            arg_count += 1;
        }
    }

    if (arg_count > 0) {
        const cmd = args[0];
        if (std.mem.eql(u8, cmd, "clear")) {
            if (arg_count == 1) {
                vga.vga_clear();
            } else {
                vga.vga_print("clear: too many arguments\n");
            }
        } else if (std.mem.eql(u8, cmd, "echo")) {
            for (1..arg_count) |j| {
                if (j > 1) vga.vga_put_char(' ');
                vga.vga_print(@as([*:0]const u8, @ptrCast(args[j].ptr)));
            }
            vga.vga_put_char('\n');
        } else if (std.mem.eql(u8, cmd, "help")) {
            if (arg_count == 1) {
                vga.vga_print("Available commands: clear, echo <text>, help, ls [dir], cd [dir], lsblk, debug\n");
            } else {
                vga.vga_print("help: too many arguments\n");
            }
        } else if (std.mem.eql(u8, cmd, "ls")) {
            if (arg_count > 2) {
                vga.vga_print("ls: too many arguments\n");
            } else {
                const cwd_ptr = shell_get_cwd();
                var cwd_slice: []const u8 = undefined;
                var cwd_len: usize = 0;
                while (cwd_ptr[cwd_len] != 0) : (cwd_len += 1) {}
                cwd_slice = cwd_ptr[0..cwd_len];

                const dir_arg = if (arg_count == 2) args[1] else cwd_slice;

                // Check if listing root directory
                if (std.mem.eql(u8, dir_arg, "/")) {
                    if (ext2.ext2_list_root_directory()) {
                        // ext2_list_root_directory prints the directory contents
                    } else {
                        vga.vga_print("ls: failed to list root\n");
                    }
                } else {
                    // For subdirectories, remove leading "/" if present
                    const path_to_list = if (dir_arg.len > 0 and dir_arg[0] == '/')
                        dir_arg[1..]
                    else
                        dir_arg;

                    // List subdirectory
                    if (ext2.ext2_list_directory(@as([*:0]const u8, @ptrCast(path_to_list.ptr)))) {
                        // ext2_list_directory prints the directory contents
                    } else {
                        vga.vga_print("ls: directory not found\n");
                    }
                }
            }
        } else if (std.mem.eql(u8, cmd, "lsblk")) {
            if (arg_count == 1) {
                ext2.ext2_show_info();
            } else {
                vga.vga_print("lsblk: too many arguments\n");
            }
        } else if (std.mem.eql(u8, cmd, "debug")) {
            vga.vga_print("debug: not implemented for ext2\n");
        } else if (std.mem.eql(u8, cmd, "cd")) {
            if (arg_count != 2) {
                vga.vga_print("cd: requires one argument\n");
            } else {
                const dir = args[1];
                // Simple directory validation
                if (std.mem.eql(u8, dir, "/") or std.mem.eql(u8, dir, "bin") or std.mem.eql(u8, dir, "/bin")) {
                    // Clear current dir and set new one
                    current_dir_len = 0;
                    @memset(&current_dir, 0);

                    if (std.mem.eql(u8, dir, "/")) {
                        current_dir[0] = '/';
                        current_dir[1] = 0;
                        current_dir_len = 1;
                    } else if (std.mem.eql(u8, dir, "bin") or std.mem.eql(u8, dir, "/bin")) {
                        current_dir[0] = '/';
                        current_dir[1] = 'b';
                        current_dir[2] = 'i';
                        current_dir[3] = 'n';
                        current_dir[4] = 0;
                        current_dir_len = 4;
                    }
                } else {
                    vga.vga_print("cd: directory not found\n");
                }
            }
        } else {
            vga.vga_print("Unknown command: ");
            vga.vga_print(@as([*:0]const u8, @ptrCast(cmd.ptr)));
            vga.vga_put_char('\n');

            // Try to load as ELF
            var elf_path: [256]u8 = [_]u8{0} ** 256;
            var path_index: usize = 0;
            const bin_prefix = "/bin/";
            for (bin_prefix, 0..) |c, idx| {
                if (idx < elf_path.len) {
                    elf_path[path_index] = c;
                    path_index += 1;
                }
            }
            for (cmd, 0..) |c, idx| {
                if (path_index + idx < elf_path.len - 4) { // .elf
                    elf_path[path_index + idx] = c;
                }
            }
            const elf_suffix = ".elf";
            for (elf_suffix, 0..) |c, idx| {
                if (path_index + cmd.len + idx < elf_path.len) {
                    elf_path[path_index + cmd.len + idx] = c;
                }
            }
            elf_path[path_index + cmd.len + elf_suffix.len] = 0;

            var buffer: [4096]u8 = [_]u8{0} ** 4096;
            var read_size: usize = 0;
            if (ext2.ext2_read_file(@as([*:0]u8, @ptrCast(&elf_path[0])), &buffer, &read_size)) {
                if (elf.elf_load(&buffer, read_size)) {
                    vga.vga_print("Loaded ELF\n");
                } else {
                    vga.vga_print("Failed to load ELF\n");
                }
            } else {
                vga.vga_print("Program not found\n");
            }
        }
    }
}
