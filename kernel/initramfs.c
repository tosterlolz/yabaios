/* Static embedded initramfs mapping for core utilities
 * This file maps 8.3 (11-byte) names to embedded binary blobs created
 * by objcopy from build/core/*.elf. If you add new core programs, add
 * entries here or update this file accordingly.
 */

#include "initramfs.h"
#include "io/string.h"
#include <stdint.h>

/* External symbols produced by objcopy -I binary on the core ELFs. The
 * symbol naming convention is _binary_<path_with_/_and_.>_start/_end
 * For example: build/core/ls.elf -> _binary_build_core_ls_elf_start
 */

extern const unsigned char _binary_build_core_ls_elf_start[];
extern const unsigned char _binary_build_core_ls_elf_end[];

extern const unsigned char _binary_build_core_echo_elf_start[];
extern const unsigned char _binary_build_core_echo_elf_end[];

extern const unsigned char _binary_build_core_cat_elf_start[];
extern const unsigned char _binary_build_core_cat_elf_end[];

extern const unsigned char _binary_build_core_touch_elf_start[];
extern const unsigned char _binary_build_core_touch_elf_end[];

extern const unsigned char _binary_build_core_edit_elf_start[];
extern const unsigned char _binary_build_core_edit_elf_end[];

static const InitramfsEntry initramfs_entries[] = {
    { "LS      ELF", _binary_build_core_ls_elf_start, _binary_build_core_ls_elf_end },
    { "ECHO    ELF", _binary_build_core_echo_elf_start, _binary_build_core_echo_elf_end },
    { "CAT     ELF", _binary_build_core_cat_elf_start, _binary_build_core_cat_elf_end },
    { "TOUCH   ELF", _binary_build_core_touch_elf_start, _binary_build_core_touch_elf_end },
    { "EDIT    ELF", _binary_build_core_edit_elf_start, _binary_build_core_edit_elf_end },
};

bool initramfs_get(const char *filename11, void *out_buffer, uint32_t *out_size) {
    for (size_t i = 0; i < sizeof(initramfs_entries)/sizeof(initramfs_entries[0]); i++) {
        if (memcmp(filename11, initramfs_entries[i].name11, 11) == 0) {
            unsigned int size = (unsigned int)(initramfs_entries[i].end - initramfs_entries[i].start);
            memcpy(out_buffer, initramfs_entries[i].start, size);
            if (out_size) *out_size = size;
            return true;
        }
    }
    return false;
}