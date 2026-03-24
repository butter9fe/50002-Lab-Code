# crt0.S — C runtime startup for DOOM running from DDR3
# Reference: smunaut doom_riscv start.S (init .bss, set sp, call main)

    .section .text.start
    .global _start

_start:
    # Set stack pointer to end of DDR3 heap region (64KB stack space)
    # Previous 4KB BRAM stack overflows during DOOM demo rendering.
    # The 256-line ddr3_cache.v handles sequential stack access fine.
    # Reference: doom.ld memory layout — heap ends at 0x20E00000
    li sp, 0x20E00000

    # Zero .bss section
    # Reference: smunaut start.S bss clearing loop
    la t0, _bss_start
    la t1, _bss_end
bss_loop:
    bge t0, t1, bss_done
    sw zero, 0(t0)
    addi t0, t0, 4
    j bss_loop
bss_done:

    # Call main(argc=0, argv=NULL)
    li a0, 0
    li a1, 0
    jal main

    # Halt on return
halt:
    j halt
