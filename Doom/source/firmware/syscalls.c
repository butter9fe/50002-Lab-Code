/* syscalls.c — Newlib syscall stubs for PicoRV32 FPGA SoC
 *
 * Reference: smunaut libc_backend.c (sbrk, file stubs, console output)
 * Reference: picorv32_soc.v IO register map (UART at 0x10000010)
 *
 * Provides the minimal syscall interface newlib needs:
 *   _sbrk, _write, _read, _open, _close, _fstat, _isatty, _lseek,
 *   _kill, _getpid, _exit
 *
 * WAD file I/O through stdio (fopen/fread) is faked here using a
 * memory-mapped blob in DDR3. The main WAD access path goes through
 * w_file_memory.c (wad_file_class_t), but DOOM also uses stdio for
 * M_FileExists and M_FileLength checks.
 */

#include <sys/stat.h>
#include <sys/types.h>
#include <errno.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>

/* Hardware registers -- Reference: picorv32_soc.v
 * UART uses simpleuart.v: writes stall CPU via reg_dat_wait. */
#define IO_BASE       0x10000000
#define REG_UART_DATA (*(volatile uint32_t *)(IO_BASE + 0x10))
#define REG_LED       (*(volatile uint32_t *)(IO_BASE + 0x00))

/* WAD location in DDR3 — must match w_file_memory.c and upload_doom.py */
#define WAD_ADDR       ((uint8_t *)0x20100000)
#define WAD_SIZE_ADDR  ((volatile uint32_t *)0x200FFFF0)

/* Fake file position for WAD fd
 * Reference: smunaut libc_backend.c file position tracking */
static off_t wad_pos = 0;

/* ---- Low-level debug print (no newlib dependency) ---- */
/* Reference: smunaut console.c — direct UART character output
 * Used for debugging before/during newlib init, and in _sbrk
 * where calling printf would cause infinite recursion. */

static void dbg_putc(char c)
{
    (void)c;
}

static void dbg_puts(const char *s)
{
    while (*s) dbg_putc(*s++);
}

/* CRITICAL: No local arrays on stack! The DDR3 LRU cache only has
 * 4 entries (16 bytes). Stack-allocated arrays get evicted and read
 * back corrupted. Use arithmetic instead of lookup tables. */

static void dbg_puthex(uint32_t val)
{
    dbg_puts("0x");
    for (int i = 28; i >= 0; i -= 4) {
        uint32_t nibble = (val >> i) & 0xF;
        /* Arithmetic instead of table lookup — no stack memory needed */
        dbg_putc(nibble < 10 ? '0' + nibble : 'A' + nibble - 10);
    }
}

static void dbg_putdec(uint32_t val)
{
    /* Print decimal without stack buffer — emit digits recursively
     * using only registers (no stack-allocated arrays) */
    if (val == 0) { dbg_putc('0'); return; }
    /* Find highest power of 10 */
    uint32_t div = 1;
    while (div * 10 <= val) div *= 10;
    /* Print digits from most significant */
    while (div > 0) {
        dbg_putc('0' + (val / div));
        val %= div;
        div /= 10;
    }
}

/* ---- sbrk: heap allocator ---- */

/* Heap for malloc — placed after WAD region in DDR3
 * Reference: smunaut libc_backend.c sbrk implementation
 * Reference: smunaut libc_backend.c LIBC_DEBUG — prints heap extensions */
static char *heap_end = (char *)0x20600000;
#define HEAP_LIMIT    ((char *)0x20E00000)  /* 8MB heap */

void *_sbrk(ptrdiff_t incr)
{
    char *prev = heap_end;
    if (heap_end + incr > HEAP_LIMIT) {
        dbg_puts("[sbrk] FAIL: heap would exceed limit. incr=");
        dbg_putdec((uint32_t)incr);
        dbg_puts(" end=");
        dbg_puthex((uint32_t)heap_end);
        dbg_puts("\r\n");
        REG_LED = 0xE1;  /* sbrk failure indicator */
        errno = ENOMEM;
        return (void *)-1;
    }
    heap_end += incr;
    dbg_puts("[sbrk] heap=");
    dbg_puthex((uint32_t)heap_end);
    dbg_puts(" (+");
    dbg_putdec((uint32_t)incr);
    dbg_puts(")\r\n");
    return prev;
}

/* ---- Console output via UART ---- */
/* Reference: smunaut console.c — character-by-character UART write
 * Must wait for TX busy flag to clear before each byte,
 * otherwise characters are dropped at 921600 baud. */
ssize_t _write(int fd, const void *buf, size_t count)
{
    (void)fd; (void)buf;
    return count;
}

/* ---- File I/O stubs ---- */

/* _open: return a fake fd for .wad files so M_FileExists succeeds.
 * Reference: doomgeneric/m_misc.c M_FileExists — calls fopen("doom1.wad","r")
 * Reference: smunaut libc_backend.c — similar WAD file stub */
int _open(const char *name, int flags, int mode)
{
    dbg_puts("[open] ");
    if (name) dbg_puts(name);
    if (name) {
        int len = strlen(name);
        if (len >= 4 &&
            (name[len-4] == '.') &&
            (name[len-3] == 'w' || name[len-3] == 'W') &&
            (name[len-2] == 'a' || name[len-2] == 'A') &&
            (name[len-1] == 'd' || name[len-1] == 'D')) {
            wad_pos = 0;
            dbg_puts(" -> fd=3\r\n");
            return 3;  /* fake fd for WAD files */
        }
    }
    dbg_puts(" -> ENOENT\r\n");
    errno = ENOENT;
    return -1;
}

/* _read: read from WAD memory blob for fd 3
 * Reference: smunaut libc_backend.c — memcpy from flash at fixed address
 *
 * Smunaut uses plain memcpy because flash reads are inherently reliable.
 * Our DDR3 reads go through the Alchitry LRU cache, where memcpy is
 * unreliable (compiler may reorder/combine accesses). Use volatile
 * word-by-word reads, same pattern as W_Memory_Read in w_file_memory.c. */
ssize_t _read(int fd, void *buf, size_t count)
{
    if (fd == 3) {
        uint32_t wad_size = *WAD_SIZE_ADDR;
        if ((uint32_t)wad_pos >= wad_size) return 0;
        if ((uint32_t)(wad_pos + count) > wad_size)
            count = wad_size - wad_pos;

        volatile uint8_t *src = (volatile uint8_t *)(WAD_ADDR + wad_pos);
        uint8_t *dst = (uint8_t *)buf;
        size_t i = 0;

        /* Align to word boundary */
        while (i < count && ((uintptr_t)(src + i) & 3)) {
            dst[i] = src[i];
            i++;
        }
        /* Word-aligned copy */
        while (i + 4 <= count) {
            volatile uint32_t *ws = (volatile uint32_t *)(src + i);
            uint32_t word = *ws;
            dst[i]   = word & 0xFF;
            dst[i+1] = (word >> 8) & 0xFF;
            dst[i+2] = (word >> 16) & 0xFF;
            dst[i+3] = (word >> 24) & 0xFF;
            i += 4;
        }
        /* Remaining bytes */
        while (i < count) {
            dst[i] = src[i];
            i++;
        }

        wad_pos += count;
        return count;
    }
    return 0;
}

int _close(int fd)
{
    return 0;
}

int _fstat(int fd, struct stat *st)
{
    if (fd == 3) {
        /* Fake WAD file — report size for M_FileLength
         * Reference: doomgeneric/m_misc.c M_FileLength */
        st->st_mode = S_IFREG;
        st->st_size = *WAD_SIZE_ADDR;
        return 0;
    }
    st->st_mode = S_IFCHR;
    return 0;
}

int _isatty(int fd)
{
    return (fd <= 2) ? 1 : 0;
}

off_t _lseek(int fd, off_t offset, int whence)
{
    if (fd == 3) {
        uint32_t wad_size = *WAD_SIZE_ADDR;
        switch (whence) {
            case SEEK_SET: wad_pos = offset; break;
            case SEEK_CUR: wad_pos += offset; break;
            case SEEK_END: wad_pos = (off_t)wad_size + offset; break;
        }
        return wad_pos;
    }
    return 0;
}

/* ---- Filesystem stubs ---- */
/* Reference: smunaut libc_backend.c — stub filesystem operations */

int mkdir(const char *path, mode_t mode)
{
    (void)path; (void)mode;
    errno = ENOSYS;
    return -1;
}

/* ---- Process stubs ---- */

void _exit(int status)
{
    dbg_puts("\r\n[EXIT] status=");
    dbg_putdec((uint32_t)status);
    dbg_puts("\r\n");
    REG_LED = 0xEE;  /* Error indicator on LEDs */
    while (1) ;
}

int _kill(int pid, int sig)
{
    errno = EINVAL;
    return -1;
}

int _getpid(void)
{
    return 1;
}
