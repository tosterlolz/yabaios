// grep - search text
#include "../kernel/kernel.h"
#include "../kernel/io/string.h"

void _start() {
    struct program_args *args = program_args();

    if (!args || args->argc < 2) {
        kernel_api()->log_print("grep: missing pattern\n");
        return;
    }

    const char *pattern = args->argv[1];
    const char *filename = (args->argc >= 3) ? args->argv[2] : NULL;

    if (!filename) {
        kernel_api()->log_print("grep: missing file argument\n");
        return;
    }

    if (kernel_api()->fat_read_file) {
        unsigned char *buffer = (unsigned char *)0x2000000;
        int size = kernel_api()->fat_read_file(filename, buffer, 100000);
        
        if (size > 0) {
            int line = 1;
            int col = 0;
            
            for (int i = 0; i < size; i++) {
                if (buffer[i] == '\n') {
                    line++;
                    col = 0;
                    continue;
                }
                
                // Simple substring search
                int match = 1;
                for (int j = 0; j < kernel_api()->strlen(pattern); j++) {
                    if (i + j >= size || buffer[i + j] != pattern[j]) {
                        match = 0;
                        break;
                    }
                }
                
                if (match) {
                    kernel_api()->log_print(filename);
                    kernel_api()->log_print(":");
                    kernel_api()->log_print_int(line);
                    kernel_api()->log_print(": ");
                    for (int j = i; j < size && buffer[j] != '\n'; j++) {
                        char c = buffer[j];
                        kernel_api()->log_putchar(c);
                    }
                    kernel_api()->log_print("\n");
                }
                
                col++;
            }
        } else {
            kernel_api()->log_print("grep: cannot read file '");
            kernel_api()->log_print(filename);
            kernel_api()->log_print("'\n");
        }
    } else {
        kernel_api()->log_print("grep: fat_read_file not available\n");
    }
}
