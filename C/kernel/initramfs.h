#ifndef INITRAMFS_H
#define INITRAMFS_H

#include <stdint.h>
#include <stdbool.h>

typedef struct {
    char name11[12]; // 11 chars + null
    const unsigned char *start;
    const unsigned char *end;
} InitramfsEntry;

bool initramfs_get(const char *filename11, void *out_buffer, uint32_t *out_size);

#endif
