// wc - word/line/character count
#include "../kernel/kernel.h"
#include "../kernel/io/string.h"

void _start() {
    struct program_args *args = program_args();

    if (!args || args->argc < 2) {
        kernel_api()->log_print("wc: missing file argument\n");
        return;
    }

    const char *filename = args->argv[1];

    if (kernel_api()->fat_read_file) {
        unsigned char *buffer = (unsigned char *)0x2000000;
        int size = kernel_api()->fat_read_file(filename, buffer, 100000);
        
        if (size > 0) {
            int lines = 0;
            int words = 0;
            int chars = 0;
            int in_word = 0;
            
            for (int i = 0; i < size; i++) {
                chars++;
                
                if (buffer[i] == '\n') {
                    lines++;
                    in_word = 0;
                } else if (buffer[i] == ' ' || buffer[i] == '\t') {
                    in_word = 0;
                } else {
                    if (!in_word) {
                        words++;
                        in_word = 1;
                    }
                }
            }
            
            kernel_api()->log_print_int(lines);
            kernel_api()->log_print(" ");
            kernel_api()->log_print_int(words);
            kernel_api()->log_print(" ");
            kernel_api()->log_print_int(chars);
            kernel_api()->log_print(" ");
            kernel_api()->log_print(filename);
            kernel_api()->log_print("\n");
        } else {
            kernel_api()->log_print("wc: cannot read file '");
            kernel_api()->log_print(filename);
            kernel_api()->log_print("'\n");
        }
    } else {
        kernel_api()->log_print("wc: fat_read_file not available\n");
    }
}
