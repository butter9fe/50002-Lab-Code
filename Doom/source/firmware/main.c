/* main.c — Minimal DOOM entry point for PicoRV32 FPGA SoC
 * Reference: picorv32_soc.v IO register map */

#include <stdint.h>
#include <stdio.h>
#include "doomgeneric.h"

#define IO_BASE   0x10000000
#define REG_LED       (*(volatile uint32_t *)(IO_BASE + 0x00))
#define REG_UART_DATA (*(volatile uint32_t *)(IO_BASE + 0x10))
#define REG_TIMER     (*(volatile uint32_t *)(IO_BASE + 0x20))

/* Visible delay so user can read LED codes
 * Reference: picorv32_soc.v timer at IO+0x20, 81.25 MHz */
static void delay_ms(uint32_t ms)
{
    uint32_t start = REG_TIMER;
    uint32_t ticks = ms * 81250;
    while ((REG_TIMER - start) < ticks)
        ;
}

int main(int argc, char **argv)
{
    REG_LED = 0x01;  /* stage 1: main reached */
    delay_ms(1000);

    REG_LED = 0x02;  /* stage 2: about to call doomgeneric_Create */
    delay_ms(1000);

    static char *doom_argv[] = {
        "doom",
        "-iwad",
        "doom1.wad",
        NULL
    };

    doomgeneric_Create(3, doom_argv);

    REG_LED = 0x00;  /* game loop running */

    /* Main game loop — call doomgeneric_Tick each frame
     * Reference: doomgeneric_sdl.c, doomgeneric_xlib.c (all platforms do this)
     * LED[0] toggles each frame as heartbeat — blinking = alive, stuck = hung */
    uint32_t frame = 0;
    for (;;) {
        REG_LED = (frame & 1);  /* heartbeat: toggles LED[0] each frame */
        doomgeneric_Tick();
        frame++;
    }

    return 0;
}
