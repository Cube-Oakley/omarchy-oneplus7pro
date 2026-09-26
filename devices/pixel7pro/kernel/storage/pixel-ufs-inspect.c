// SPDX-License-Identifier: GPL-2.0-only
/* Read-only GS201 UFS handoff inventory. Never changes a register.
 * Register definitions: Linux ufshci.h and pinned Google ufs-exynos sources.
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
    check_range("ufs@0x14700000", 0x14700000, 0x200);
    if (!access("/sys/bus/platform/devices/14700000.ufs/driver", F_OK) ||
        !access("/sys/bus/platform/devices/pixel-ufs/driver", F_OK)) {
        fputs("Refusing inspection while a UFS driver is bound\n", stderr); return 1;
    }
    fd = open("/dev/mem", O_RDONLY | O_SYNC);
    if (fd < 0) die("/dev/mem");
    const unsigned hci[] = {0, 8, 0x10, 0x20, 0x24, 0x30, 0x34, 0x50, 0x54,
                            0x58, 0x60, 0x70, 0x74, 0x78, 0x80};
    const unsigned vendor[] = {0, 4, 0xc, 0x40, 0x44, 0x50, 0x60, 0x68,
                               0x6c, 0x70, 0xb0, 0xb4, 0x100};
    dump(fd, 0x14700000, 0x1000, "UFS_HCI", hci, sizeof(hci)/sizeof(*hci));
    /* Vendor block begins at page offset 0x100. All listed registers are
     * configuration/status (no interrupt-clear or FIFO reads). */
    volatile const uint32_t *v = map(fd, 0x14701000, 0x1000);
    for (size_t i=0; i<sizeof(vendor)/sizeof(*vendor); i++)
        printf("UFS_VENDOR +%04x = %08x\n", vendor[i], v[(0x100+vendor[i])/4]);
    munmap((void *)v, 0x1000);
    close(fd);
    return 0;
}
