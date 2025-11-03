#include "keyboard.h"
#include "../io/io.h"
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define PORT_DATA 0x60
#define PORT_STATUS 0x64

#define KB_BUFFER_SIZE 64

static const char keymap[128] = {
    [0x01] = 27,
    [0x02] = '1', [0x03] = '2', [0x04] = '3', [0x05] = '4',
    [0x06] = '5', [0x07] = '6', [0x08] = '7', [0x09] = '8',
    [0x0A] = '9', [0x0B] = '0', [0x0C] = '-', [0x0D] = '=',
    [0x0E] = '\b',
    [0x0F] = '\t',
    [0x10] = 'q', [0x11] = 'w', [0x12] = 'e', [0x13] = 'r',
    [0x14] = 't', [0x15] = 'y', [0x16] = 'u', [0x17] = 'i',
    [0x18] = 'o', [0x19] = 'p', [0x1A] = '[', [0x1B] = ']',
    [0x1C] = '\n',
    [0x1E] = 'a', [0x1F] = 's', [0x20] = 'd', [0x21] = 'f',
    [0x22] = 'g', [0x23] = 'h', [0x24] = 'j', [0x25] = 'k',
    [0x26] = 'l', [0x27] = ';', [0x28] = '\'', [0x29] = '`',
    [0x2B] = '\\',
    [0x2C] = 'z', [0x2D] = 'x', [0x2E] = 'c', [0x2F] = 'v',
    [0x30] = 'b', [0x31] = 'n', [0x32] = 'm', [0x33] = ',',
    [0x34] = '.', [0x35] = '/',
    [0x37] = '*',
    [0x39] = ' '
};

static const char keymap_shift[128] = {
    [0x01] = 27,
    [0x02] = '!', [0x03] = '@', [0x04] = '#', [0x05] = '$',
    [0x06] = '%', [0x07] = '^', [0x08] = '&', [0x09] = '*',
    [0x0A] = '(', [0x0B] = ')', [0x0C] = '_', [0x0D] = '+',
    [0x0E] = '\b',
    [0x0F] = '\t',
    [0x1A] = '{', [0x1B] = '}',
    [0x27] = ':', [0x28] = '"', [0x29] = '~',
    [0x2B] = '|',
    [0x33] = '<', [0x34] = '>', [0x35] = '?',
    [0x37] = '*',
    [0x39] = ' '
};

static char key_buffer[KB_BUFFER_SIZE];
static size_t buffer_head = 0;
static size_t buffer_tail = 0;

static bool left_shift = false;
static bool right_shift = false;
static bool caps_lock = false;
static bool extended_code = false;

static bool buffer_empty(void) {
    return buffer_head == buffer_tail;
}

static void buffer_push(char c) {
    size_t next = (buffer_head + 1) % KB_BUFFER_SIZE;
    if (next != buffer_tail) {
        key_buffer[buffer_head] = c;
        buffer_head = next;
    }
}

static char buffer_pop(void) {
    if (buffer_empty()) {
        return 0;
    }
    char c = key_buffer[buffer_tail];
    buffer_tail = (buffer_tail + 1) % KB_BUFFER_SIZE;
    return c;
}

static void keyboard_process_scancode(uint8_t scancode) {
    if (scancode == 0xE0) {
        extended_code = true;
        return;
    }

    bool release = scancode & 0x80;
    uint8_t code = scancode & 0x7F;

    if (extended_code) {
        /* Ignore extended keys for now */
        extended_code = false;
        return;
    }

    switch (code) {
        case 0x2A: /* Left Shift */
            left_shift = !release;
            return;
        case 0x36: /* Right Shift */
            right_shift = !release;
            return;
        case 0x3A: /* Caps Lock */
            if (!release) {
                caps_lock = !caps_lock;
            }
            return;
        default:
            break;
    }

    if (release) {
        return;
    }

    if (code >= 128) {
        return;
    }

    char base = keymap[code];
    if (!base) {
        return;
    }

    bool shift_active = left_shift || right_shift;
    char ch = base;

    if (shift_active && keymap_shift[code]) {
        ch = keymap_shift[code];
    }

    if (base >= 'a' && base <= 'z') {
        bool uppercase = caps_lock;
        if (shift_active) {
            uppercase = !uppercase;
        }
        if (uppercase) {
            ch = (char)(base - 'a' + 'A');
        } else {
            ch = base;
        }
    }

    buffer_push(ch);
}

void keyboard_init() {
    buffer_head = buffer_tail = 0;
    left_shift = right_shift = false;
    caps_lock = false;
    extended_code = false;
}

void keyboard_handle_input() {
    while (io_in8(PORT_STATUS) & 1) {
        uint8_t scancode = io_in8(PORT_DATA);
        keyboard_process_scancode(scancode);
    }
}

char keyboard_get_char() {
    keyboard_handle_input();
    return buffer_pop();
}
