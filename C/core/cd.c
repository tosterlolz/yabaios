// cd - change directory
#include "../kernel/kernel.h"

void _start() {
    struct program_args *args = program_args();

    if (!args || args->argc < 2) {
        kernel_api()->log_print("usage: cd <path>\n");
        return;
    }

    const char *path = args->argv[1];
    const char *target = path;
    char resolved[256];

    if (path[0] == '.' && path[1] == '.' && path[2] == '\0') {
        const char *cwd = kernel_api()->get_cwd();
        int len = 0;

        if (cwd) {
            while (cwd[len] != '\0' && len < (int)(sizeof(resolved) - 1)) {
                resolved[len] = cwd[len];
                len++;
            }
        }
        resolved[len] = '\0';

        if (len == 0) {
            resolved[0] = '/';
            resolved[1] = '\0';
            len = 1;
        }

        while (len > 1 && resolved[len - 1] == '/') {
            resolved[len - 1] = '\0';
            len--;
        }

        int last_slash = -1;
        for (int i = len - 1; i >= 0; --i) {
            if (resolved[i] == '/') {
                last_slash = i;
                break;
            }
        }

        if (last_slash <= 0) {
            resolved[0] = '/';
            resolved[1] = '\0';
        } else {
            resolved[last_slash] = '\0';
        }

        target = resolved;
    }

    if (kernel_api()->set_cwd(target) == 0) {
        kernel_api()->log_print("cd: changed to ");
        kernel_api()->log_print(target);
        kernel_api()->log_print("\n");
    } else {
        kernel_api()->log_print("cd: failed to change directory\n");
    }
}
