#include "fat.h"
#include "../io/log.h"
#include "../io/string.h"

static uint8_t *fat_image = 0;
static FAT_BPB *bpb;
static uint32_t root_dir_offset;
static uint32_t data_offset;

bool fat_init(void *image_base) {
    fat_image = (uint8_t *)image_base;
    bpb = (FAT_BPB *)fat_image;

    if (bpb->bytesPerSector != 512) {
        log_message("FAT: Unsupported sector size.");
        return false;
    }

    root_dir_offset = (bpb->reservedSectors + (bpb->numFATs * bpb->sectorsPerFAT)) * bpb->bytesPerSector;
    data_offset = root_dir_offset + (bpb->rootEntryCount * sizeof(FAT_DirEntry));

    log_message("FAT: Initialized.");
    return true;
}

bool fat_read_file(const char *filename, void *out_buffer) {
    FAT_DirEntry *entries = (FAT_DirEntry *)(fat_image + root_dir_offset);

    for (int i = 0; i < bpb->rootEntryCount; i++) {
        if (entries[i].name[0] == 0x00)
            break;
        if ((entries[i].attr & 0x0F) == 0x0F)
            continue;

        char name[12];
        memcpy(name, entries[i].name, 11);
        name[11] = '\0';

        if (memcmp(name, filename, 11) == 0) {
            uint16_t cluster = entries[i].clusterLow;
            uint32_t fileSize = entries[i].fileSize;
            uint32_t bytesPerCluster = bpb->bytesPerSector * bpb->sectorsPerCluster;
            uint8_t *dest = (uint8_t *)out_buffer;

            while (cluster < 0xFF8) {
                uint32_t offset = data_offset + (cluster - 2) * bytesPerCluster;
                memcpy(dest, fat_image + offset, bytesPerCluster);
                dest += bytesPerCluster;

                uint32_t fatOffset = bpb->reservedSectors * bpb->bytesPerSector + cluster * 3 / 2;
                uint16_t nextCluster = *(uint16_t *)(fat_image + fatOffset);
                if (cluster & 1)
                    nextCluster >>= 4;
                else
                    nextCluster &= 0x0FFF;

                cluster = nextCluster;
            }

            return true;
        }
    }

    log_message("FAT: File not found.");
    return false;
}

void fat_list_files(void) {
    FAT_DirEntry *entries = (FAT_DirEntry *)(fat_image + root_dir_offset);
    log_message("FAT: Root directory:");

    for (int i = 0; i < bpb->rootEntryCount; i++) {
        // 0x00 = no more entries, 0xE5 = deleted
        if (entries[i].name[0] == 0x00)
            break;
        if ((entries[i].name[0] & 0xFF) == 0xE5)
            continue;
        // skip long-file-name entries and volume labels
        if (entries[i].attr == 0x0F)
            continue;
        if (entries[i].attr & 0x08)
            continue;

        // Build a printable filename: NAME.EXT (trim spaces)
        char name[13];
        int pos = 0;
        // name part (8 bytes)
        for (int j = 0; j < 8; j++) {
            char c = entries[i].name[j];
            if (c == ' ') break;
            name[pos++] = c;
        }
        // extension part (3 bytes)
        int extStart = pos;
        for (int j = 8; j < 11; j++) {
            char c = entries[i].name[j];
            if (c == ' ') continue;
            // if we haven't added any name chars, still append
            if (pos == extStart) {
                // add dot separator
                name[pos++] = '.';
            }
            name[pos++] = entries[i].name[j];
        }
        if (pos == 0) {
            // empty name, skip
            continue;
        }
        name[pos] = '\0';

        log_print("  ");
        log_print(name);
        log_print("\n");
    }
}
