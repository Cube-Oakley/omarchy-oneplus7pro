// SPDX-License-Identifier: GPL-2.0-only
/* Read-only DPU0 SysMMU capability inventory. No writes or page-table walk.
 * Reads only the hardware-identification registers used by samsung-iommu at
 * probe, then selects VM0 control/base from the reported VCR capability.
 * Source: kernel/gs b3c9095e01cefb36f35723b5c66638bf15f5144a.
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
static uint32_t sample(volatile const uint32_t *r, unsigned off, const char *name)
{
    printf("reading %s +%04x\n", name, off);
    uint32_t value = r[off / 4];
    printf("%s = %08x\n", name, value);
    return value;
}
int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    char compat[256] = {0};
    int fd = open("/sys/firmware/devicetree/base/compatible", O_RDONLY);
    if (fd < 0) die("compatible");
    ssize_t n = read(fd, compat, sizeof(compat)-1); close(fd);
    if (n <= 0 || strcmp(compat, "google,GS201 CHEETAH")) return 1;
    if (access("/sys/bus/platform/drivers/pixel-handoff/pixel-handoff", F_OK))
        die("retained display driver must be bound");
    check_range("sysmmu@1C100000", 0x1c100000, 0x10000);
    fd = open("/dev/mem", O_RDONLY | O_SYNC);
    if (fd < 0) die("/dev/mem");
    volatile const uint32_t *pmu = map(fd, 0x18062000, 0x1000);
    uint32_t dpu = pmu[0x204/4], disp = pmu[0x284/4];
    munmap((void *)pmu, 0x1000);
    printf("power status dpu=%#x disp=%#x\n", dpu, disp);
    if (!(dpu & 1) || !(disp & 1)) return 1;
    volatile const uint32_t *r = map(fd, 0x1c100000, 0x10000);
    uint32_t version = sample(r, 0x34, "VERSION");
    uint32_t raw = (version >> 17) & 0x7fff;
    unsigned major = raw >> 11, minor = (raw >> 4) & 0x7f, rev = raw & 15;
    printf("SysMMU version %u.%u.%u\n", major, minor, rev);
    if (major < 7 || major > 8) {
        fputs("Unrecognized/inaccessible hardware; no further reads\n", stderr);
        return 2;
    }
    uint32_t cap0 = sample(r, 0x870, "CAPA0");
    if (!(cap0 & (1U << 11))) {
        fputs("No CAPA1 advertised; stopping\n", stderr); return 2;
    }
    uint32_t cap1 = sample(r, 0x874, "CAPA1");
    printf("VCR=%u no_block=%u TLBs=%u ports=%u\n",
           !!(cap1 & (1U << 14)), !!(cap1 & (1U << 15)),
           (cap1 >> 4) & 255, cap1 & 15);
    sample(r, 0x0, "GLOBAL_CTRL");
    sample(r, 0x4, "GLOBAL_CFG");
    sample(r, 0x8, "GLOBAL_STATUS");
    if (cap1 & (1U << 14)) {
        sample(r, 0x8000, "VM0_CTRL");
        sample(r, 0x8004, "VM0_CFG");
        sample(r, 0x800c, "VM0_FLPT_BASE");
    } else {
        fputs("Non-VM layout: base read deliberately deferred\n", stderr);
    }
    munmap((void *)r, 0x10000);
    close(fd);
    return 0;
}
