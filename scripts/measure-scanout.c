/* Read-only timing sample of guacamole's retained bootloader framebuffer.
 * Read its address/geometry from DT; never write /dev/mem or display registers.
 * Run while quickshell-frame-test.qml is visible; samples its 30,30 marker.
 * Counts framebuffer updates, not physical panel refreshes.
 */
#define _FILE_OFFSET_BITS 64
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <time.h>

static void property(const char *name, void *buf, size_t size) {
    char path[256];
    snprintf(path, sizeof(path), "/sys/firmware/devicetree/base/chosen/framebuffer@9C000000/%s", name);
    int fd = open(path, O_RDONLY);
    if (fd < 0) { perror(path); exit(1); }
    if (read(fd, buf, size) != (ssize_t)size) { fprintf(stderr, "Invalid property: %s\n", name); exit(1); }
    close(fd);
}

int main(void) {
    uint64_t reg[2];
    uint32_t w, h, stride;
    char format[9];
    property("reg", reg, sizeof(reg));
    property("width", &w, sizeof(w));
    property("height", &h, sizeof(h));
    property("stride", &stride, sizeof(stride));
    property("format", format, sizeof(format));
    uint64_t base = __builtin_bswap64(reg[0]), size = __builtin_bswap64(reg[1]);
    w = __builtin_bswap32(w); h = __builtin_bswap32(h); stride = __builtin_bswap32(stride);
    if (base != 0x9c000000 || size != 17971200 || w != 1440 || h != 3120 || stride != 5760 ||
        memcmp(format, "a8r8g8b8", 9)) {
        fprintf(stderr, "Framebuffer does not match known guacamole layout\n"); return 1;
    }
    int fd = open("/dev/mem", O_RDONLY | O_SYNC);
    if (fd < 0) { perror("/dev/mem"); return 1; }
    const volatile uint32_t *pixels = mmap(NULL, size, PROT_READ, MAP_SHARED, fd, base);
    if (pixels == MAP_FAILED) { perror("mmap scanout"); close(fd); return 1; }
    printf("scanout=%#llx %ux%u stride=%u center=%08x\n", (unsigned long long)base,
           w, h, stride, pixels[(h / 2) * (stride / 4) + w / 2]);
    // Fixed 30,30 physical-pixel marker in the temporary test surface.
    const size_t offset = 30 * (stride / 4) + 30;
    struct timespec start, now, delay = {.tv_nsec = 1000000};
    clock_gettime(CLOCK_MONOTONIC, &start);
    uint32_t previous = pixels[offset];
    double elapsed = 0;
    printf("seconds,pixel\n0.000000,%08x\n", previous);
    while (elapsed < 12.0) {
        nanosleep(&delay, NULL);
        clock_gettime(CLOCK_MONOTONIC, &now);
        elapsed = now.tv_sec - start.tv_sec + (now.tv_nsec - start.tv_nsec) / 1e9;
        uint32_t value = pixels[offset];
        if (value != previous) {
            printf("%.6f,%08x\n", elapsed, value);
            previous = value;
        }
    }
    munmap((void *)pixels, size);
    close(fd);
    return 0;
}
