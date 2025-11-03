#ifndef IO_H
#define IO_H

#include <stdint.h>

uint8_t io_in8(uint16_t port);
void io_out8(uint16_t port, uint8_t val);
uint16_t io_in16(uint16_t port);
void io_out16(uint16_t port, uint16_t val);
uint32_t io_in32(uint16_t port);
void io_out32(uint16_t port, uint32_t val);

#endif
