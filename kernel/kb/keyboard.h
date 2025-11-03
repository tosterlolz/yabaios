#ifndef KB_KEYBOARD_H
#define KB_KEYBOARD_H

#include <stdint.h>

void keyboard_init();
void keyboard_handle_input();
char keyboard_get_char();

#endif
