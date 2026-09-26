// SPDX-License-Identifier: GPL-2.0-only
/* Read-only GS201 display handoff inventory. Never changes a register.
 * Register definitions: pinned Google cal_9845 and samsung-iommu sources.
 */
#define _GNU_SOURCE
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

static void die(const char *what) { perror(what); exit(1); }
static uint32_t be32(const unsigned char *p)
{ return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3]; }
static void check_range(const char *node, uint64_t address, uint32_t size)
{
    char path[256]; unsigned char reg[128], cells[4];
    int fd = open("/sys/firmware/devicetree/base/#address-cells", O_RDONLY);
    if (fd < 0 || read(fd, cells, 4) != 4 || be32(cells) != 2) die("address cells");
    close(fd);
    fd = open("/sys/firmware/devicetree/base/#size-cells", O_RDONLY);
    if (fd < 0 || read(fd, cells, 4) != 4 || be32(cells) != 1) die("size cells");
    close(fd);
    snprintf(path, sizeof(path), "/sys/firmware/devicetree/base/%s/reg", node);
    fd = open(path, O_RDONLY);
    if (fd < 0) die(path);
    ssize_t n = read(fd, reg, sizeof(reg)); close(fd);
    if (n < 12 || n % 12 || (((uint64_t)be32(reg) << 32) | be32(reg+4)) != address ||
        be32(reg+8) != size) {
        fprintf(stderr, "Unexpected DT range for %s\n", node); exit(1);
    }
}
static volatile const uint32_t *map(int fd, uint64_t address, size_t size)
{
    void *p = mmap(NULL, size, PROT_READ, MAP_SHARED, fd, address);
    if (p == MAP_FAILED) die("read-only mmap");
    return p;
}
static void dump(int fd, uint64_t base, size_t size, const char *name,
                 const unsigned *offsets, size_t count)
{
    printf("Reading %s @ %#llx\n", name, (unsigned long long)base);
    volatile const uint32_t *r = map(fd, base, size);
    for (size_t i=0; i<count; i++) printf("%s +%04x = %08x\n", name, offsets[i], r[offsets[i]/4]);
    munmap((void *)r, size);
}
int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    char compat[256] = {0};
    int fd = open("/sys/firmware/devicetree/base/compatible", O_RDONLY);
    if (fd < 0) die("compatible");
    ssize_t n = read(fd, compat, sizeof(compat)-1); close(fd);
    if (n <= 0 || strcmp(compat, "google,GS201 CHEETAH")) {
        fputs("Expected cheetah\n", stderr); return 1;
    }
    if (access("/sys/bus/platform/drivers/pixel-handoff/pixel-handoff", F_OK))
        die("retained display driver must be bound");
    check_range("drmdpp@0x1C0B0000", 0x1c0b0000, 0x1000);
    check_range("drmdecon@0x1C240000", 0x1c240000, 0x6000);
    check_range("drmdsim@0x1C2C0000", 0x1c2c0000, 0x300);
    fd = open("/dev/mem", O_RDONLY | O_SYNC);
    if (fd < 0) die("/dev/mem");
    volatile const uint32_t *pmu = map(fd, 0x18062000, 0x1000);
    uint32_t dpu = pmu[0x204/4], disp = pmu[0x284/4];
    munmap((void *)pmu, 0x1000);
    printf("power status dpu=%#x disp=%#x\n", dpu, disp);
    if (!(dpu & 1) || !(disp & 1)) { fputs("Display domains are off\n", stderr); return 1; }
    /* cal_9845 also dumps the active RDMA shadow bank at DMA_SHD_OFFSET. */
    const unsigned dma[] = {0, 4, 8, 0x10, 0x14, 0x40, 0x50,
                            0x408, 0x410, 0x414, 0x440, 0x450};
    const unsigned decon[] = {0, 4, 0x20, 0x30, 0x50, 0x60, 0x64, 0x70, 0x74};
    const unsigned dsim[] = {0, 8, 0xc, 0x14, 0x18, 0x1c, 0x20, 0x24, 0x28};
    dump(fd, 0x1c0b0000, 0x1000, "DPP0_DMA", dma, sizeof(dma)/sizeof(*dma));
    dump(fd, 0x1c240000, 0x1000, "DECON0", decon, sizeof(decon)/sizeof(*decon));
    /* SysMMU access needs its own clock/security driver; do not probe it here. */
    dump(fd, 0x1c2c0000, 0x1000, "DSIM0", dsim, sizeof(dsim)/sizeof(*dsim));
    close(fd);
    return 0;
}
