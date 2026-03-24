// Bootloader: receive program over UART, write to DDR3, jump to it.
// Protocol:
//   1. PC sends 4-byte little-endian size (in bytes)
//   2. PC sends <size> bytes of program data
//   3. Bootloader writes to DDR3 starting at 0x20000000
//   4. Bootloader jumps to 0x20000000
//
// LED status: 0x01 = waiting, 0x02 = receiving, 0x03 = jumping

    .section .text.start
    .global _start

    .equ IO_BASE,    0x10000000
    .equ LED_OFF,    0x00
    .equ UART_DATA,  0x10
    .equ DDR_BASE,   0x20000000

_start:
    li sp, 0x00001000       // stack at top of BRAM
    li s0, IO_BASE           // s0 = IO base (persistent)
    li s1, DDR_BASE          // s1 = DDR base (persistent)

    // LED = 0x01 (waiting for size)
    li t0, 0x01
    sw t0, LED_OFF(s0)

    // Receive 4-byte size (little-endian)
    jal ra, uart_recv_byte   // byte 0 (LSB)
    mv s2, a0
    jal ra, uart_recv_byte   // byte 1
    slli a0, a0, 8
    or s2, s2, a0
    jal ra, uart_recv_byte   // byte 2
    slli a0, a0, 16
    or s2, s2, a0
    jal ra, uart_recv_byte   // byte 3 (MSB)
    slli a0, a0, 24
    or s2, s2, a0
    // s2 = total byte count

    // LED = 0x02 (receiving data)
    li t0, 0x02
    sw t0, LED_OFF(s0)

    // Receive program data, accumulate 4 bytes, write as words to DDR3
    mv s3, s1               // s3 = current DDR write pointer
    add s4, s1, s2          // s4 = end address

recv_loop:
    bge s3, s4, recv_done

    // Accumulate 4 bytes into a word (little-endian)
    li s5, 0                // word accumulator
    li s6, 0                // byte index (0-3)

word_loop:
    bge s3, s4, partial_write  // end of data mid-word
    li t0, 4
    bge s6, t0, word_done      // got 4 bytes

    jal ra, uart_recv_byte
    slli t0, s6, 3            // t0 = s6 * 8 (bit position)
    sll t0, a0, t0            // t0 = byte << (s6*8)
    or s5, s5, t0
    addi s6, s6, 1
    addi s3, s3, 1
    j word_loop

word_done:
    // Write full word to DDR3
    // Address = s3 - 4 (we already advanced s3 by 4)
    addi t0, s3, -4
    sw s5, 0(t0)
    j recv_loop

partial_write:
    // Write partial word (last 1-3 bytes)
    // Address = word-aligned start of this group
    andi t0, s3, ~3           // align down
    sub t0, s3, s6            // start of this word = s3 - s6
    sw s5, 0(t0)

recv_done:
    // LED = 0x03 (jumping)
    li t0, 0x03
    sw t0, LED_OFF(s0)

    // Jump to DDR3 start
    jr s1

// -----------------------------------------------
// uart_recv_byte: wait for UART RX, return byte in a0
// Reference: simpleuart.v -- read returns 0xFFFFFFFF if no data
// -----------------------------------------------
uart_recv_byte:
    lw a0, UART_DATA(s0)     // read simpleuart data register
    li t0, -1                // 0xFFFFFFFF = no data
    beq a0, t0, uart_recv_byte  // loop until data ready
    andi a0, a0, 0xFF
    ret
