// ls - list directory contents
#include "../kernel/kernel.h"

void _start() {
    struct program_args *args = program_args();

    if (!args || args->argc < 1) {
        kernel_api()->log_print("ls\n");
        return;
    }

    /* If no arguments, list current directory */
    if (args->argc == 1) {
        if (kernel_api()->fat_list_files_in_dir) {
            kernel_api()->fat_list_files_in_dir(kernel_api()->get_cwd());
        } else {
            kernel_api()->log_print("ls: fat_list_files_in_dir not available\n");
        }
        return;
    }

    /* If argument provided, list that directory */
    const char *path = args->argv[1];

    if (path[0] == '-') {
        /* Option flag - ignore for now, just list current dir */
        if (kernel_api()->fat_list_files_in_dir) {
            kernel_api()->fat_list_files_in_dir(kernel_api()->get_cwd());
        }
    } else {
        /* Path argument */
        if (kernel_api()->fat_list_files_in_dir) {
            kernel_api()->fat_list_files_in_dir(path);
        } else {
            kernel_api()->log_print("ls: fat_list_files_in_dir not available\n");
        }
    }
}

