/* doom.ld — Linker script for DOOM running from DDR3
 * Reference: smunaut riscv.lds (section layout)
 * Reference: phase4_link.ld (DDR3 base address)
 *
 * Memory layout:
 *   0x20000000  Code + rodata + data + bss  (~1MB max)
 *   0x20100000  WAD file (uploaded by host, ~4MB)
 *   0x20600000  Zone heap (8MB, returned by I_ZoneBase)
 *   0x2FF00000  Stack top (grows down)
 */

MEMORY {
    DDR (rwx) : ORIGIN = 0x20000000, LENGTH = 1M
}

ENTRY(_start)

SECTIONS {
    .text : {
        *(.text.start)     /* crt0 entry point first */
        *(.text .text.*)
    } > DDR

    .rodata : {
        *(.rodata .rodata.*)
    } > DDR

    .data : {
        *(.data .data.*)
        *(.sdata .sdata.*)
    } > DDR

    .bss (NOLOAD) : {
        _bss_start = .;
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        _bss_end = .;
    } > DDR

    _end = .;

    /DISCARD/ : {
        *(.eh_frame)
        *(.comment)
        *(.note.*)
    }
}
