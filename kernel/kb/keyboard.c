#include "keyboard.h"
#include "../io/io.h"
#include <stdbool.h>
#include <stddef.h>

#define PORT_DATA 0x60
#define PORT_STATUS 0x64

static char keymap[128] = {
    0,  27, '1','2','3','4','5','6','7','8','9','0','-','=', '\b',
    '\t', 'q','w','e','r','t','y','u','i','o','p','[',']', '\n',
    0, 'a','s','d','f','g','h','j','k','l',';','\'','`',
    0,'\\','z','x','c','v','b','n','m',',','.','/', 0, '*', 0, ' ',
};

static volatile char last_char = 0;

void keyboard_init() {
    // Nothing special for PS/2 keyboard
}

char keyboard_get_char() {
    uint8_t status = io_in8(PORT_STATUS);
    if (status & 1) {
        uint8_t scancode = io_in8(PORT_DATA);
        if (!(scancode & 0x80)) {
            if (scancode < 128) {
                char c = keymap[scancode];
                return c;
            }
        }
    }
    return 0;
}

void keyboard_handle_input() {
    (void)keyboard_get_char();
}
