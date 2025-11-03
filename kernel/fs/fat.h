#ifndef FAT_H
#define FAT_H

#include <stdint.h>
#include <stdbool.h>

typedef struct {
    uint8_t  jmpBoot[3];
    uint8_t  OEMName[8];
    uint16_t bytesPerSector;
    uint8_t  sectorsPerCluster;
    uint16_t reservedSectors;
    uint8_t  numFATs;
    uint16_t rootEntryCount;
    uint16_t totalSectors16;
    uint8_t  mediaType;
    uint16_t sectorsPerFAT;
    uint16_t sectorsPerTrack;
    uint16_t numHeads;
    uint32_t hiddenSectors;
    uint32_t totalSectors32;
} __attribute__((packed)) FAT_BPB;

typedef struct {
    uint8_t  name[11];
    uint8_t  attr;
    uint8_t  reserved;
    uint8_t  createTimeFine;
    uint16_t createTime;
    uint16_t createDate;
    uint16_t accessDate;
    uint16_t clusterHigh;
    uint16_t modifiedTime;
    uint16_t modifiedDate;
    uint16_t clusterLow;
    uint32_t fileSize;
} __attribute__((packed)) FAT_DirEntry;

bool fat_init(void *image_base);
void fat_list_files(void);
bool fat_read_file(const char *filename, void *out_buffer);

#endif
