#include "pci.h"
#include "io.h"

#define PCI_CONFIG_ADDRESS 0xCF8
#define PCI_CONFIG_DATA    0xCFC

static uint32_t pci_config_address(uint8_t bus, uint8_t slot, uint8_t function, uint8_t offset) {
    return (uint32_t)(0x80000000U | ((uint32_t)bus << 16) | ((uint32_t)slot << 11) |
                      ((uint32_t)function << 8) | (offset & 0xFC));
}

uint32_t pci_read32(uint8_t bus, uint8_t slot, uint8_t function, uint8_t offset) {
    uint32_t address = pci_config_address(bus, slot, function, offset);
    io_out32(PCI_CONFIG_ADDRESS, address);
    return io_in32(PCI_CONFIG_DATA);
}

uint16_t pci_read16(uint8_t bus, uint8_t slot, uint8_t function, uint8_t offset) {
    uint32_t shift = (offset & 2) * 8;
    uint32_t value = pci_read32(bus, slot, function, offset);
    return (uint16_t)((value >> shift) & 0xFFFF);
}

uint8_t pci_read8(uint8_t bus, uint8_t slot, uint8_t function, uint8_t offset) {
    uint32_t shift = (offset & 3) * 8;
    uint32_t value = pci_read32(bus, slot, function, offset);
    return (uint8_t)((value >> shift) & 0xFF);
}

void pci_write32(uint8_t bus, uint8_t slot, uint8_t function, uint8_t offset, uint32_t value) {
    uint32_t address = pci_config_address(bus, slot, function, offset);
    io_out32(PCI_CONFIG_ADDRESS, address);
    io_out32(PCI_CONFIG_DATA, value);
}

void pci_write16(uint8_t bus, uint8_t slot, uint8_t function, uint8_t offset, uint16_t value) {
    uint32_t address = pci_config_address(bus, slot, function, offset);
    io_out32(PCI_CONFIG_ADDRESS, address);
    uint32_t current = io_in32(PCI_CONFIG_DATA);
    uint32_t shift = (offset & 2) * 8;
    current &= ~((uint32_t)0xFFFF << shift);
    current |= ((uint32_t)value << shift);
    io_out32(PCI_CONFIG_ADDRESS, address);
    io_out32(PCI_CONFIG_DATA, current);
}

void pci_write8(uint8_t bus, uint8_t slot, uint8_t function, uint8_t offset, uint8_t value) {
    uint32_t address = pci_config_address(bus, slot, function, offset);
    io_out32(PCI_CONFIG_ADDRESS, address);
    uint32_t current = io_in32(PCI_CONFIG_DATA);
    uint32_t shift = (offset & 3) * 8;
    current &= ~((uint32_t)0xFF << shift);
    current |= ((uint32_t)value << shift);
    io_out32(PCI_CONFIG_ADDRESS, address);
    io_out32(PCI_CONFIG_DATA, current);
}

int pci_find_device(uint16_t vendor, uint16_t device, struct pci_device *out) {
    for (uint8_t bus = 0; bus < 256; ++bus) {
        for (uint8_t slot = 0; slot < 32; ++slot) {
            uint8_t functions = 1;
            uint8_t header_type = pci_read8(bus, slot, 0, 0x0E);
            if (header_type & 0x80) {
                functions = 8;
            }
            for (uint8_t function = 0; function < functions; ++function) {
                uint32_t id = pci_read32(bus, slot, function, 0x00);
                if ((id & 0xFFFF) == 0xFFFF) {
                    continue;
                }
                uint16_t vendor_id = (uint16_t)(id & 0xFFFF);
                uint16_t device_id = (uint16_t)((id >> 16) & 0xFFFF);
                if (vendor_id == vendor && device_id == device) {
                    if (out) {
                        out->bus = bus;
                        out->slot = slot;
                        out->function = function;
                        out->vendor_id = vendor_id;
                        out->device_id = device_id;
                        out->bar0 = pci_read32(bus, slot, function, 0x10);
                    }
                    return 1;
                }
            }
        }
    }
    return 0;
}

void pci_set_command_bits(const struct pci_device *dev, uint16_t bits) {
    if (!dev) {
        return;
    }
    uint16_t command = pci_read16(dev->bus, dev->slot, dev->function, 0x04);
    if ((command & bits) != bits) {
        command |= bits;
        pci_write16(dev->bus, dev->slot, dev->function, 0x04, command);
    }
}
