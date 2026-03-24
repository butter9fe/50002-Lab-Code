    .section .text.start
    .global _start
_start:
    /* Set stack pointer to top of BRAM */
    li sp, 0x00001000
    /* Jump to C main */
    call main
    /* Halt if main returns */
1:  j 1b
