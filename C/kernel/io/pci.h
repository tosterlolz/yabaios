#ifndef IO_PCI_H
#define IO_PCI_H

#include <stdint.h>
#include <stdbool.h>

struct pci_device {
    uint8_t bus;
    uint8_t slot;
    uint8_t function;
    uint16_t vendor_id;
    uint16_t device_id;
    uint32_t bar0;
};

#define PCI_COMMAND_IO      0x0001
#define PCI_COMMAND_MEMORY  0x0002
#define PCI_COMMAND_MASTER  0x0004

uint32_t pci_read32(uint8_t bus, uint8_t slot, uint8_t function, uint8_t offset);
uint16_t pci_read16(uint8_t bus, uint8_t slot, uint8_t function, uint8_t offset);
uint8_t pci_read8(uint8_t bus, uint8_t slot, uint8_t function, uint8_t offset);
void pci_write32(uint8_t bus, uint8_t slot, uint8_t function, uint8_t offset, uint32_t value);
void pci_write16(uint8_t bus, uint8_t slot, uint8_t function, uint8_t offset, uint16_t value);
void pci_write8(uint8_t bus, uint8_t slot, uint8_t function, uint8_t offset, uint8_t value);

int pci_find_device(uint16_t vendor, uint16_t device, struct pci_device *out);
void pci_set_command_bits(const struct pci_device *dev, uint16_t bits);

#endif
