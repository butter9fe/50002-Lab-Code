/* w_file_memory.c — WAD file I/O from memory-mapped DDR3
 *
 * Reference: doomgeneric/w_file_stdc.c (wad_file_class_t interface)
 * Reference: doomgeneric/w_file.h (wad_file_t.mapped field for zero-copy access)
 * Reference: smunaut libc_backend.c (in-memory WAD blob approach)
 *
 * The WAD file is uploaded to DDR3 at a fixed address by the host.
 * We return a wad_file_t with the 'mapped' pointer set, so w_wad.c
 * can read lump data directly from DDR3 with zero copies.
 */

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "w_file.h"
#include "z_zone.h"

/* WAD location in DDR3 — set by upload.py padding scheme */
#define WAD_ADDR       ((uint8_t *)0x20100000)
#define WAD_SIZE_ADDR  ((uint32_t *)0x200FFFF0)

/* Export as 'stdc_wad_file' — this is the symbol w_file.c expects.
 * By naming it stdc_wad_file, we act as a drop-in replacement for
 * w_file_stdc.c without modifying any doomgeneric source files.
 * Reference: doomgeneric/w_file.c line 28, 50, 65 */
extern wad_file_class_t stdc_wad_file;

static wad_file_t *W_Memory_OpenFile(char *path)
{
    wad_file_t *result;

    printf("[w_file_memory] OpenFile: path=%s\n", path ? path : "(null)");

    result = Z_Malloc(sizeof(wad_file_t), PU_STATIC, 0);
    result->file_class = &stdc_wad_file;

    /* Do NOT set mapped pointer. Direct DDR3 reads via non-volatile
     * pointers are unreliable through the LRU cache. Instead, force
     * all reads through W_Memory_Read (volatile) and let DOOM cache
     * lump data in zone memory (also DDR3, but written by CPU). */
    result->mapped = NULL;
    result->length = *(volatile uint32_t *)WAD_SIZE_ADDR;

    /* Read first 4 bytes to verify WAD header */
    volatile uint32_t *hdr = (volatile uint32_t *)WAD_ADDR;
    printf("[w_file_memory] WAD length=%u, header=0x%08X\n",
           (unsigned)result->length, (unsigned)*hdr);

    return result;
}

static void W_Memory_CloseFile(wad_file_t *wad)
{
    Z_Free(wad);
}

/* Read from DDR3 using volatile pointer to prevent compiler
 * optimizing reads (memcpy doesn't work reliably through the
 * LRU cache — compiler may reorder or combine DDR3 accesses).
 * Reference: w_file_stdc.c W_StdC_Read */
static size_t W_Memory_Read(wad_file_t *wad, unsigned int offset,
                            void *buffer, size_t buffer_len)
{
    if (offset + buffer_len > wad->length) {
        if (offset >= wad->length)
            return 0;
        buffer_len = wad->length - offset;
    }

    volatile uint8_t *src = (volatile uint8_t *)(WAD_ADDR + offset);
    uint8_t *dst = (uint8_t *)buffer;

    /* Word-aligned copy for speed where possible */
    size_t i = 0;
    /* Align to word boundary */
    while (i < buffer_len && ((uintptr_t)(src + i) & 3)) {
        dst[i] = src[i];
        i++;
    }
    /* Word copy */
    while (i + 4 <= buffer_len) {
        volatile uint32_t *ws = (volatile uint32_t *)(src + i);
        uint32_t word = *ws;
        dst[i]   = word & 0xFF;
        dst[i+1] = (word >> 8) & 0xFF;
        dst[i+2] = (word >> 16) & 0xFF;
        dst[i+3] = (word >> 24) & 0xFF;
        i += 4;
    }
    /* Remaining bytes */
    while (i < buffer_len) {
        dst[i] = src[i];
        i++;
    }

    return buffer_len;
}

wad_file_class_t stdc_wad_file =
{
    W_Memory_OpenFile,
    W_Memory_CloseFile,
    W_Memory_Read,
};
