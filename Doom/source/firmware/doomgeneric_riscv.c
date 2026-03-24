/* doomgeneric_riscv.c — Platform implementation for PicoRV32 FPGA SoC
 *
 * Reference: doomgeneric/doomgeneric.h (DG_* interface)
 * Reference: smunaut doom_riscv doomgeneric_riscv.c (palette + framebuffer copy)
 * Reference: picorv32_soc.v (IO register map)
 *
 * Implements the 6 platform functions required by doomgeneric:
 *   DG_Init, DG_DrawFrame, DG_SleepMs, DG_GetTicksMs, DG_GetKey, DG_SetWindowTitle
 */

#include "doomgeneric.h"
#include "doomkeys.h"
#include "i_video.h"

#include <string.h>
#include <stdint.h>
#include <stdio.h>

/* ---- Hardware register map (from picorv32_soc.v IO region) ---- */
/* UART uses simpleuart.v: single data register for both TX and RX.
 * Read returns byte or 0xFFFFFFFF if no data. Write stalls CPU until free. */
#define IO_BASE       0x10000000
#define REG_LED       (*(volatile uint32_t *)(IO_BASE + 0x00))
#define REG_UART_DATA (*(volatile uint32_t *)(IO_BASE + 0x10))
#define REG_TIMER     (*(volatile uint32_t *)(IO_BASE + 0x20))

/* ---- Framebuffer + palette hardware (from alchitry_top.luc) ---- */
#define FB_BASE       ((volatile uint8_t *)0x30000000)
#define PAL_BASE      ((volatile uint32_t *)0x30100000)

/* ---- Clock frequency: MIG ui_clk = 81.25 MHz ---- */
#define CLK_FREQ_HZ   81250000
#define TICKS_PER_MS  (CLK_FREQ_HZ / 1000)

/* ---- Button input (memory-mapped IO register) ---- */
/* Reference: picorv32_soc.v IO region — buttons at 0x10000030
 * Bits [4:0] = right, left, down, fire, up (active high) */
#define REG_BUTTONS   (*(volatile uint32_t *)(IO_BASE + 0x30))

#define BTN_UP    (1 << 0)
#define BTN_FIRE  (1 << 1)
#define BTN_DOWN  (1 << 2)
#define BTN_LEFT  (1 << 3)
#define BTN_RIGHT (1 << 4)

/* Key queue for DG_GetKey
 * Reference: doomgeneric_sdl.c key queue pattern */
#define KEY_QUEUE_SIZE 16
static struct {
    int pressed;
    unsigned char key;
} key_queue[KEY_QUEUE_SIZE];
static int key_queue_head = 0;
static int key_queue_tail = 0;

static void key_queue_push(int pressed, unsigned char key)
{
    key_queue[key_queue_head].pressed = pressed;
    key_queue[key_queue_head].key = key;
    key_queue_head = (key_queue_head + 1) % KEY_QUEUE_SIZE;
}

/* Previous button state for edge detection */
static uint32_t prev_buttons = 0;

/* Poll hardware buttons and push edge-detected key events
 * Reference: picorv32_soc.v buttons register at IO+0x30 */
static void process_button_input(void)
{
    uint32_t cur = REG_BUTTONS & 0x1F;
    uint32_t changed = cur ^ prev_buttons;
    prev_buttons = cur;

    if (!changed) return;

    /* For each button, detect press/release edges */
    static const struct { uint32_t mask; unsigned char key; } btn_map[] = {
        { BTN_UP,    KEY_UPARROW },
        { BTN_DOWN,  KEY_DOWNARROW },
        { BTN_LEFT,  KEY_LEFTARROW },
        { BTN_RIGHT, KEY_RIGHTARROW },
        { BTN_FIRE,  KEY_FIRE },
    };

    for (int i = 0; i < 5; i++) {
        if (changed & btn_map[i].mask) {
            int pressed = (cur & btn_map[i].mask) ? 1 : 0;
            key_queue_push(pressed, btn_map[i].key);
        }
    }

}

/* Map ASCII/control bytes from UART to DOOM key codes
 * Reference: doomgeneric/doomkeys.h */
static void process_uart_input(void)
{
    uint32_t rx;
    while ((rx = REG_UART_DATA) != 0xFFFFFFFF) {
        uint8_t c = rx & 0xFF;

        /* Protocol: 0x80 | key = press, 0x00 | key = release
         * Keys: 'w'=up, 's'=down, 'a'=left, 'd'=right, ' '=fire, 'e'=use,
         *        '\r'=enter, 0x1b=escape */
        int pressed = (c & 0x80) ? 1 : 0;
        c &= 0x7F;

        unsigned char doomkey = 0;
        switch (c) {
            case 'w': doomkey = KEY_UPARROW;    break;
            case 's': doomkey = KEY_DOWNARROW;   break;
            case 'a': doomkey = KEY_LEFTARROW;   break;
            case 'd': doomkey = KEY_RIGHTARROW;  break;
            case ' ': doomkey = KEY_FIRE;        break;
            case 'e': doomkey = KEY_USE;         break;
            case '\r': doomkey = KEY_ENTER;      break;
            case 0x1b: doomkey = KEY_ESCAPE;     break;
            case 'q': doomkey = KEY_STRAFE_L;    break;
            case 'r': doomkey = KEY_STRAFE_R;    break;
            case ',': doomkey = KEY_RALT;        break;  /* alt/strafe */
            case '.': doomkey = KEY_RSHIFT;      break;  /* run */
            default: continue;
        }

        key_queue_push(pressed, doomkey);
    }
}

/* ---- DG_Init ---- */
/* Reference: doomgeneric.h
 * Reference: smunaut i_video.c I_InitGraphics — minimal init */
void DG_Init(void)
{
    REG_LED = 0xD0;  /* LED indicator: DOOM video init */
    printf("[DG_Init] Framebuffer at 0x30000000, Palette at 0x30100000\n");
    printf("[DG_Init] Resolution: 320x200, 8-bit indexed color\n");
}

/* ---- DG_DrawFrame ---- */
/* Reference: smunaut i_video.c I_FinishUpdate (framebuffer copy)
 * Reference: smunaut i_video.c I_SetPalette (palette write)
 *
 * With CMAP256 defined, DG_ScreenBuffer contains 8-bit palette indices.
 * Copy to hardware framebuffer. Also update palette if changed. */
void DG_DrawFrame(void)
{
    /* Copy palette indices to hardware framebuffer
     * Reference: smunaut i_video.c — memcpy screen to framebuffer
     *
     * Must use byte writes (sb) because the SoC framebuffer interface
     * is 8 bits wide (one palette index per write).
     * Reference: picorv32_soc.v fb_wdata is [7:0] */
    const uint8_t *src = (const uint8_t *)DG_ScreenBuffer;
    volatile uint8_t *dst = FB_BASE;
    for (int i = 0; i < 320 * 200; i++) {
        dst[i] = src[i];
    }

    /* Update palette if changed
     * Reference: smunaut i_video.c I_SetPalette — write RGB to hardware */
#ifdef CMAP256
    if (palette_changed) {
        palette_changed = false;
        for (int i = 0; i < 256; i++) {
            /* Pack as 0x00RRGGBB matching palette RAM format
             * Reference: picorv32_soc.v palette write (pal_wdata = mem_wdata[23:0]) */
            uint32_t rgb = ((uint32_t)colors[i].r << 16) |
                           ((uint32_t)colors[i].g << 8)  |
                           ((uint32_t)colors[i].b);
            PAL_BASE[i] = rgb;
        }
    }
#endif

    /* Poll hardware buttons for input each frame */
    process_button_input();

    /* Also poll UART for input (keyboard proxy from host) */
    process_uart_input();
}

/* ---- DG_SleepMs ---- */
/* Reference: doomgeneric.h */
void DG_SleepMs(uint32_t ms)
{
    uint32_t start = REG_TIMER;
    uint32_t wait = ms * TICKS_PER_MS;
    while ((REG_TIMER - start) < wait)
        ;
}

/* ---- DG_GetTicksMs ---- */
/* Reference: doomgeneric.h
 * Timer counts at CLK_FREQ_HZ (81.25 MHz).
 * The 32-bit hardware timer wraps every ~52.8 seconds (2^32 / 81.25MHz).
 * We track elapsed ticks across wraps using delta accumulation.
 * Reference: picorv32_soc.v timer register at IO+0x20 */
static uint32_t last_timer = 0;
static uint32_t total_ms = 0;
static uint32_t residual_ticks = 0;

uint32_t DG_GetTicksMs(void)
{
    uint32_t now = REG_TIMER;
    uint32_t delta = now - last_timer;  /* handles wrap via unsigned subtraction */
    last_timer = now;

    residual_ticks += delta;
    uint32_t new_ms = residual_ticks / TICKS_PER_MS;
    residual_ticks -= new_ms * TICKS_PER_MS;
    total_ms += new_ms;

    return total_ms;
}

/* ---- DG_GetKey ---- */
/* Reference: doomgeneric.h, doomgeneric_sdl.c key queue pattern */
int DG_GetKey(int *pressed, unsigned char *doomKey)
{
    if (key_queue_tail == key_queue_head)
        return 0;

    *pressed = key_queue[key_queue_tail].pressed;
    *doomKey = key_queue[key_queue_tail].key;
    key_queue_tail = (key_queue_tail + 1) % KEY_QUEUE_SIZE;
    return 1;
}

/* ---- DG_SetWindowTitle ---- */
/* Reference: doomgeneric.h — no-op on embedded */
void DG_SetWindowTitle(const char *title)
{
    (void)title;
}
