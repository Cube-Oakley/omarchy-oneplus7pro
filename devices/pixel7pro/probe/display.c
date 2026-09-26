/* SPDX-License-Identifier: GPL-2.0-only
 * Cheetah / cloudripper 15.1 standalone RAM probe, not a Linux kernel.
 * MMIO addresses: verified live GS201 DT and Google cal_9845 + cal_9855.
 * Refresh sequence: this phone's ABL decon_reg_start/all_win_shadow_update.
 * No storage, firmware, clocks, power, DSI or DMA-address programming.
 */
typedef unsigned int u32;
typedef unsigned long u64;
#include "font.h"

#define FB 0xfac00000UL
#define DMA 0x1c0b0000UL
#define DECON 0x1c240000UL
#define LOG 0xfd3ff000UL /* live DT ramoops console, 2 MiB, no ECC */
#define W 1440
#define H 3120

extern void probe_reset(void) __attribute__((noreturn));
static inline u32 rd(u64 addr) { return *(volatile u32 *)addr; }
static inline void wr(u64 addr, u32 v) { *(volatile u32 *)addr = v; }
static inline void barrier(void) { __asm__ volatile("dsb sy" ::: "memory"); }
static u64 ticks(void) { u64 v; __asm__ volatile("mrs %0, cntvct_el0" : "=r"(v)); return v; }
static u64 frequency(void) { u64 v; __asm__ volatile("mrs %0, cntfrq_el0" : "=r"(v)); return v; }
static void wait_ms(u32 ms) {
    u64 start = ticks(), duration = frequency() * ms / 1000;
    while (ticks() - start < duration) __asm__ volatile("yield");
}

/* Verified DT reservation, console layout and ECC=0. Every append is committed
 * for diagnosis after even an exception/reset. No storage writes. */
static void logchar(char c) {
    u32 n;
    if (rd(LOG) != 0x43474244) return;
    n = rd(LOG + 8);
    if (n >= 4095) return;
    *(volatile unsigned char *)(LOG + 12 + n) = c;
    barrier();
    wr(LOG + 4, n + 1);
    wr(LOG + 8, n + 1);
    barrier();
}
static void logstr(const char *s) { while (*s) logchar(*s++); }
static void hex(u64 v, char *s) {
    for (int i = 0; i < 16; i++) s[i] = "0123456789abcdef"[(v >> (60 - i * 4)) & 15];
    s[16] = 0;
}
static void logval(const char *name, u64 v) {
    char s[17]; hex(v, s); logstr(name); logstr(s); logstr("\n");
}
static void text(int y, const char *s) {
    int col = 0;
    while (*s && col < 56) {
        unsigned char c = *s++;
        for (int gy = 0; gy < 16; gy++)
            for (int gx = 0; gx < 8; gx++) {
                u32 color = (font[c * 16 + gy] & (128 >> gx)) ? 0xffffffff : 0xff181818;
                for (int dy = 0; dy < 3; dy++)
                    for (int dx = 0; dx < 3; dx++)
                        wr(FB + ((u64)(y + gy * 3 + dy) * W + 48 + col * 24 + gx * 3 + dx) * 4, color);
            }
        col++;
    }
}
static void lineval(int y, const char *name, u64 v) {
    char s[17]; text(y, name); hex(v, s); text(y + 50, s);
}
static void flush(void) {
    u32 trigger = rd(DECON + 0x30);
    barrier();
    wr(DECON + 0x50, rd(DECON + 0x50) | 0x3f);
    wr(DECON + 0x20, rd(DECON + 0x20) | 3);
    wr(DECON + 0x50, rd(DECON + 0x50) | 0x80100000);
    /* Keep existing TE source; unmask its hardware trigger like ABL. */
    wr(DECON + 0x30, (trigger & ~0x10U) | 1);
    barrier();
    u64 start = ticks(), timeout = frequency() / 3;
    while (rd(DECON + 0x50) && ticks() - start < timeout) {}
    wr(DECON + 0x30, trigger);
    barrier();
}
void probe_exception(u64 esr, u64 pc, u64 far) {
    logstr("EXCEPTION\n"); logval("ESR=", esr);
    logval("PC=", pc); logval("FAR=", far);
    probe_reset();
}
void probe_main(u64 fdt, u64 el) {
    wr(LOG + 4, 0); wr(LOG + 8, 0); wr(LOG, 0x43474244); barrier();
    logstr("PIXEL-FB-PROBE v2 entered\n");
    logval("EL=", el); logval("FDT=", fdt);
    logval("CNTFRQ=", frequency());
    logstr("Reading DECON0 and DPP0\n");
    u32 base = rd(DMA + 0x40), size = rd(DMA + 0x10);
    u32 ctrl = rd(DMA + 8), format = (ctrl >> 8) & 63;
    u32 global = rd(DECON + 0x20), trigger = rd(DECON + 0x30);
    u32 stride = rd(DMA + 0x50), stride0 = rd(DMA + 0x54) & 0xffff;
    logval("BASE=", base); logval("SIZE=", size); logval("CTRL=", ctrl);
    logval("SHADOW_BASE=", rd(DMA + 0x440));
    logval("OFFSET=", rd(DMA + 0x14)); logval("IMAGE_SIZE=", rd(DMA + 0x18));
    logval("STRIDE_SEL=", stride); logval("STRIDE0=", stride0);
    logval("GLOBAL=", global); logval("TRIGGER=", trigger);
    logval("FRAME_BEFORE=", rd(DECON + 4));
    /* Fail closed if the retained scanout does not match the known buffer.
     * Only uncompressed 32-bit RGB with contiguous rows and zero crop. */
    if (base != FB || size != ((u32)H << 16 | W) || format > 7 ||
        rd(DMA + 0x14) || (ctrl & 7U) ||
        ((stride & (1U << 20)) && stride0 != W * 4) ||
        !(global & (1U << 8)) || !(trigger & 0x11) || (trigger & 0x102)) {
        logstr("Guard mismatch: framebuffer unchanged; reset in 12s\n");
        wait_ms(12000); probe_reset();
    }
    logstr("Guards passed; drawing banner\n");
    for (int y = 700; y < 1800; y++)
        for (int x = 0; x < W; x++) wr(FB + ((u64)y * W + x) * 4, 0xff181818);
    text(740, "PIXEL 7 PRO - RAM DISPLAY PROBE");
    text(820, "BOOT FRAMEBUFFER HANDOFF TEST");
    lineval(940, "DPP0 FRAMEBUFFER ADDRESS", base);
    lineval(1070, "PIXEL FORMAT", format);
    lineval(1200, "DECON TRIGGER", trigger);
    text(1400, "PHOTO THIS SCREEN IF VISIBLE");
    text(1480, "AUTOMATIC REBOOT IN 40 SECONDS");
    text(1560, "NO PARTITIONS WERE FLASHED");
    barrier();
    logstr("Pixels written; waiting 2s before explicit refresh\n");
    wait_ms(2000);
    flush();
    logval("FRAME_AFTER=", rd(DECON + 4));
    logval("UPDATE_AFTER=", rd(DECON + 0x50));
    logstr("Refresh attempted; reset in 40s\n");
    wait_ms(40000);
    logstr("Resetting now\n");
    probe_reset();
}
