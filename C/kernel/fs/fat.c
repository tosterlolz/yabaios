#include "fat.h"
#include "../io/log.h"
#include "../io/string.h"
#include <stdint.h>
#include <stddef.h>

static uint8_t *fat_image = 0;
static FAT_BPB *bpb;
static uint32_t root_dir_offset;
static uint32_t data_offset;

bool fat_init(void *image_base) {
    uint8_t *base = (uint8_t *)image_base;
    
    log_message("FAT: fat_init called");
    
    // Log the first bytes to see what we're actually receiving
    log_print("FAT: First 32 bytes: ");
    for (int i = 0; i < 32; i++) {
        log_put_char("0123456789ABCDEF"[(base[i] >> 4) & 0xF]);
        log_put_char("0123456789ABCDEF"[base[i] & 0xF]);
        if ((i + 1) % 16 == 0) log_put_char('\n');
    }
    
    // First, look for the boot signature 0x55AA to confirm we have valid sectors
    uint8_t *candidate_offset = NULL;
    
    // Scan for boot signature in first 2KB
    for (int offset = 0; offset < 2048; offset += 512) {
        if (base[offset + 510] == 0x55 && base[offset + 511] == 0xAA) {
            log_hex("FAT: Found boot signature at offset ", offset);
            candidate_offset = base + offset;
            break;
        }
    }
    
    if (!candidate_offset) {
        log_message("FAT: No boot signature found");
        return false;
    }
    
    // Now validate the BPB fields
    FAT_BPB *candidate = (FAT_BPB *)candidate_offset;
    uint16_t bps = candidate->bytesPerSector;
    uint8_t spc = candidate->sectorsPerCluster;
    uint16_t rsv = candidate->reservedSectors;
    uint16_t spf = candidate->sectorsPerFAT;
    uint32_t total = candidate->totalSectors32 ? candidate->totalSectors32 : candidate->totalSectors16;
    
    log_hex("FAT: BPS=", bps);
    log_hex("FAT: SPC=", spc);
    log_hex("FAT: RSV=", rsv);
    log_hex("FAT: SPF=", spf);
    log_hex("FAT: Total=", total);
    
    if (bps != 512 || spc < 1 || spc > 128 || rsv == 0 || spf == 0 || total == 0) {
        log_message("FAT: BPB fields invalid");
        return false;
    }
    
    fat_image = candidate_offset;
    bpb = candidate;

    // compute commonly used offsets
    root_dir_offset = (bpb->reservedSectors + (bpb->numFATs * bpb->sectorsPerFAT)) * bpb->bytesPerSector;
    data_offset = root_dir_offset + (bpb->rootEntryCount * sizeof(FAT_DirEntry));

    log_message("FAT: Initialized.");
    return true;
}

bool fat_read_file_in_dir(const char *dir11, const char *filename11, void *out_buffer, uint32_t *out_size) {
    // find directory entry in root
    FAT_DirEntry *root = (FAT_DirEntry *)(fat_image + root_dir_offset);
    int dirIndex = -1;
    for (int i = 0; i < bpb->rootEntryCount; i++) {
        if (root[i].name[0] == 0x00) break;
        if ((root[i].name[0] & 0xFF) == 0xE5) continue;
        if (root[i].attr & 0x08) continue; // volume
        if (memcmp(root[i].name, dir11, 11) == 0 && (root[i].attr & 0x10)) {
            dirIndex = i; break;
        }
    }
    if (dirIndex < 0) return false;

    uint16_t cluster = root[dirIndex].clusterLow;
    if (cluster < 2) return false;

    uint32_t bytesPerCluster = bpb->bytesPerSector * bpb->sectorsPerCluster;

    while (cluster < 0xFF8) {
        uint32_t offset = data_offset + (cluster - 2) * bytesPerCluster;
        FAT_DirEntry *entries = (FAT_DirEntry *)(fat_image + offset);
        int entriesCount = bytesPerCluster / sizeof(FAT_DirEntry);
        for (int i = 0; i < entriesCount; i++) {
            if (entries[i].name[0] == 0x00) return false;
            if ((entries[i].name[0] & 0xFF) == 0xE5) continue;
            if ((entries[i].attr & 0x0F) == 0x0F) continue;
            if (entries[i].attr & 0x08) continue;
            if (memcmp(entries[i].name, filename11, 11) == 0) {
                // found file in subdir
                uint16_t fcluster = entries[i].clusterLow;
                uint32_t fileSize = entries[i].fileSize;
                uint8_t *dest = (uint8_t *)out_buffer;
                uint32_t remaining = fileSize;
                while (fcluster < 0xFF8 && remaining > 0) {
                    uint32_t off = data_offset + (fcluster - 2) * bytesPerCluster;
                    uint32_t toCopy = (remaining < bytesPerCluster) ? remaining : bytesPerCluster;
                    memcpy(dest, fat_image + off, toCopy);
                    dest += toCopy;
                    remaining -= toCopy;

                    uint32_t fatOffset = bpb->reservedSectors * bpb->bytesPerSector + fcluster * 3 / 2;
                    uint16_t nextCluster = *(uint16_t *)(fat_image + fatOffset);
                    if (fcluster & 1)
                        nextCluster >>= 4;
                    else
                        nextCluster &= 0x0FFF;
                    fcluster = nextCluster;
                }
                if (out_size) *out_size = fileSize - remaining;
                return true;
            }
        }
        // next cluster in directory chain
        uint32_t fatOffset = bpb->reservedSectors * bpb->bytesPerSector + cluster * 3 / 2;
        uint16_t nextCluster = *(uint16_t *)(fat_image + fatOffset);
        if (cluster & 1) nextCluster >>= 4; else nextCluster &= 0x0FFF;
        if (nextCluster >= 0xFF8) break;
        cluster = nextCluster;
    }
    return false;
}

bool fat_read_file(const char *filename, void *out_buffer, uint32_t *out_size) {
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
            uint32_t remaining = fileSize;

            while (cluster < 0xFF8 && remaining > 0) {
                uint32_t offset = data_offset + (cluster - 2) * bytesPerCluster;
                uint32_t toCopy = (remaining < bytesPerCluster) ? remaining : bytesPerCluster;
                memcpy(dest, fat_image + offset, toCopy);
                dest += toCopy;
                remaining -= toCopy;

                uint32_t fatOffset = bpb->reservedSectors * bpb->bytesPerSector + cluster * 3 / 2;
                uint16_t nextCluster = *(uint16_t *)(fat_image + fatOffset);
                if (cluster & 1)
                    nextCluster >>= 4;
                else
                    nextCluster &= 0x0FFF;

                cluster = nextCluster;
            }

            if (out_size) *out_size = fileSize - remaining;
            return true;
        }
    }

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
        // name part (8 bytes) - copy only printable ASCII, stop at space
        for (int j = 0; j < 8; j++) {
            unsigned char c = entries[i].name[j];
            if (c == ' ') break;
            if (c < 0x20 || c > 0x7E) break; // non-printable
            name[pos++] = (char)c;
        }
        // extension part (3 bytes)
        int extStart = pos;
        for (int j = 8; j < 11; j++) {
            unsigned char c = entries[i].name[j];
            if (c == ' ') continue;
            if (c < 0x20 || c > 0x7E) continue;
            // if we haven't added any name chars for extension, add separator
            if (pos == extStart) {
                name[pos++] = '.';
            }
            name[pos++] = (char)c;
        }
        if (pos == 0) {
            // empty name, skip
            continue;
        }
        name[pos] = '\0';

        for (int j = 0; name[j]; j++) {
            if (name[j] >= 'A' && name[j] <= 'Z') {
                name[j] = (char)(name[j] - 'A' + 'a');
            }
        }

        log_print("  ");
        log_print(name);
        log_print("\n");
    }
}

void fat_list_files_in_dir(const char *path) {
    if (!path || path[0] == '\0' || (path[0] == '/' && path[1] == '\0')) {
        /* Root directory */
        fat_list_files();
        return;
    }

    /* Convert path to 8.3 format and look it up */
    uint8_t dir_name11[11];
    fat_format_83_name(path, dir_name11);

    /* List files in root directory to find the subdirectory */
    FAT_DirEntry *root_entries = (FAT_DirEntry *)(fat_image + root_dir_offset);

    for (int i = 0; i < bpb->rootEntryCount; i++) {
        if (root_entries[i].name[0] == 0x00)
            break;
        if ((root_entries[i].name[0] & 0xFF) == 0xE5)
            continue;
        if (root_entries[i].attr == 0x0F)
            continue;

        /* Check if this is a directory entry matching our path */
        if (memcmp(root_entries[i].name, dir_name11, 11) == 0 && (root_entries[i].attr & 0x10)) {
            /* Found directory, list its contents */
            uint16_t cluster = root_entries[i].clusterLow;
            uint32_t bytesPerCluster = bpb->sectorsPerCluster * bpb->bytesPerSector;
            uint32_t data_offset = (bpb->reservedSectors + bpb->numFATs * bpb->sectorsPerFAT + 
                                   (bpb->rootEntryCount * 32 + bpb->bytesPerSector - 1) / bpb->bytesPerSector) * 
                                  bpb->bytesPerSector;

            log_message("FAT: Directory listing:");

            while (cluster < 0xFF8) {
                uint32_t dir_offset = data_offset + (cluster - 2) * bytesPerCluster;
                FAT_DirEntry *dir_entries = (FAT_DirEntry *)(fat_image + dir_offset);

                for (int j = 0; j < bytesPerCluster / sizeof(FAT_DirEntry); j++) {
                    if (dir_entries[j].name[0] == 0x00)
                        return;
                    if ((dir_entries[j].name[0] & 0xFF) == 0xE5)
                        continue;
                    if (dir_entries[j].attr == 0x0F)
                        continue;
                    if (dir_entries[j].attr & 0x08)
                        continue;

                    /* Build printable filename */
                    char name[13];
                    int pos = 0;
                    for (int k = 0; k < 8; k++) {
                        unsigned char c = dir_entries[j].name[k];
                        if (c == ' ') break;
                        if (c < 0x20 || c > 0x7E) break;
                        name[pos++] = (char)c;
                    }
                    int extStart = pos;
                    for (int k = 8; k < 11; k++) {
                        unsigned char c = dir_entries[j].name[k];
                        if (c == ' ') continue;
                        if (c < 0x20 || c > 0x7E) continue;
                        if (pos == extStart) {
                            name[pos++] = '.';
                        }
                        name[pos++] = (char)c;
                    }
                    if (pos == 0) continue;
                    name[pos] = '\0';

                    /* Convert to lowercase */
                    for (int k = 0; name[k]; k++) {
                        if (name[k] >= 'A' && name[k] <= 'Z') {
                            name[k] = (char)(name[k] - 'A' + 'a');
                        }
                    }

                    log_print("  ");
                    log_print(name);
                    log_print("\n");
                }

                /* Get next cluster */
                uint32_t fatOffset = bpb->reservedSectors * bpb->bytesPerSector + cluster * 3 / 2;
                uint16_t nextCluster = *(uint16_t *)(fat_image + fatOffset);
                if (cluster & 1) nextCluster >>= 4;
                else nextCluster &= 0x0FFF;
                if (nextCluster >= 0xFF8) break;
                cluster = nextCluster;
            }
            return;
        }
    }

    log_message("FAT: Directory not found");
}

// --- Minimal FAT12 helpers for creating small files (one cluster) ---
static uint16_t fat_get_entry(uint16_t cluster) {
    uint32_t fatOffset = bpb->reservedSectors * bpb->bytesPerSector + cluster * 3 / 2;
    uint16_t val = *(uint16_t *)(fat_image + fatOffset);
    if (cluster & 1)
        val >>= 4;
    else
        val &= 0x0FFF;
    return val;
}

static void fat_set_entry(uint16_t cluster, uint16_t value) {
    uint32_t fatStart = bpb->reservedSectors * bpb->bytesPerSector;
    uint32_t fatSizeBytes = bpb->sectorsPerFAT * bpb->bytesPerSector;
    for (uint8_t f = 0; f < bpb->numFATs; f++) {
        uint32_t fatOffset = fatStart + f * fatSizeBytes + cluster * 3 / 2;
        uint8_t *p = fat_image + fatOffset;
        uint16_t cur = *(uint16_t *)p;
        if (cluster & 1) {
            // odd cluster: store high 12 bits
            cur &= 0x000F;
            cur |= (value << 4) & 0xFFF0;
        } else {
            // even cluster: store low 12 bits
            cur &= 0xF000;
            cur |= value & 0x0FFF;
        }
        *(uint16_t *)p = cur;
    }
}

static int find_free_cluster(void) {
    // compute max clusters in data area
    uint32_t rootDirSectors = (bpb->rootEntryCount * 32 + bpb->bytesPerSector - 1) / bpb->bytesPerSector;
    uint32_t firstDataSector = bpb->reservedSectors + (bpb->numFATs * bpb->sectorsPerFAT) + rootDirSectors;
    uint32_t totalDataSectors = bpb->totalSectors32 - firstDataSector;
    uint32_t maxClusters = totalDataSectors / bpb->sectorsPerCluster + 2;

    for (uint16_t c = 2; c < maxClusters; c++) {
        uint16_t entry = fat_get_entry(c);
        if (entry == 0x000) return c;
    }
    return -1;
}

static int find_free_root_entry(void) {
    FAT_DirEntry *entries = (FAT_DirEntry *)(fat_image + root_dir_offset);
    for (int i = 0; i < bpb->rootEntryCount; i++) {
        if (entries[i].name[0] == 0x00 || (entries[i].name[0] & 0xFF) == 0xE5) return i;
    }
    return -1;
}

void fat_format_83_name(const char *src, uint8_t dest[11]) {
    // Fill with spaces
    for (int i = 0; i < 11; i++) dest[i] = ' ';
    // Copy name and extension
    int di = 0;
    // copy name up to '.' or up to 8 chars
    int si = 0;
    while (src[si] && src[si] != '.' && di < 8) {
        char c = src[si];
        if (c >= 'a' && c <= 'z') c -= 32;
        dest[di++] = (uint8_t)c;
        si++;
    }
    if (src[si] == '.') si++;
    // copy extension up to 3 chars
    di = 8;
    int ei = 0;
    while (src[si] && ei < 3) {
        char c = src[si++];
        if (c >= 'a' && c <= 'z') c -= 32;
        dest[di++] = (uint8_t)c;
        ei++;
    }
}

bool fat_create_file(const char *filename) {
    int idx = find_free_root_entry();
    if (idx < 0) return false;
    FAT_DirEntry *entries = (FAT_DirEntry *)(fat_image + root_dir_offset);
    // set name
    fat_format_83_name(filename, entries[idx].name);
    entries[idx].attr = 0x00;
    entries[idx].reserved = 0;
    entries[idx].createTimeFine = 0;
    entries[idx].createTime = 0;
    entries[idx].createDate = 0;
    entries[idx].accessDate = 0;
    entries[idx].clusterHigh = 0;
    entries[idx].modifiedTime = 0;
    entries[idx].modifiedDate = 0;
    entries[idx].clusterLow = 0;
    entries[idx].fileSize = 0;
    return true;
}

bool fat_write_file(const char *filename, const void *data, uint32_t size) {
    // find directory entry
    FAT_DirEntry *entries = (FAT_DirEntry *)(fat_image + root_dir_offset);
    uint8_t name11[11];
    fat_format_83_name(filename, name11);
    int found = -1;
    for (int i = 0; i < bpb->rootEntryCount; i++) {
        if (entries[i].name[0] == 0x00) break;
        if ((entries[i].name[0] & 0xFF) == 0xE5) continue;
        if (memcmp(entries[i].name, name11, 11) == 0) { found = i; break; }
    }
    if (found == -1) {
        // create entry
        if (!fat_create_file(filename)) return false;
        // find it
        for (int i = 0; i < bpb->rootEntryCount; i++) {
            if (memcmp(entries[i].name, name11, 11) == 0) { found = i; break; }
        }
        if (found == -1) return false;
    }

    uint32_t bytesPerCluster = bpb->bytesPerSector * bpb->sectorsPerCluster;
    if (size > bytesPerCluster) return false; // only support single-cluster writes for simplicity

    int cluster = find_free_cluster();
    if (cluster < 0) return false;

    // mark cluster as end-of-chain (0xFFF)
    fat_set_entry(cluster, 0x0FFF);

    // write data into cluster
    uint32_t offset = data_offset + (cluster - 2) * bytesPerCluster;
    memcpy(fat_image + offset, data, size);

    // update directory entry
    entries[found].clusterLow = (uint16_t)cluster;
    entries[found].fileSize = size;
    return true;
}
