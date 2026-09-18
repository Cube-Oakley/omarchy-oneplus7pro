/* Read-only snapshot of guacamole's retained bootloader framebuffer.
 * Read its address/geometry from DT; never write /dev/mem or display registers.
 * Usage: read-scanout [output.ppm]  (PPM is sampled at 1/4 resolution).
 */
#define _FILE_OFFSET_BITS 64
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

static void property(const char *name, void *buf, size_t size) {
    char path[256];
    snprintf(path, sizeof(path), "/sys/firmware/devicetree/base/chosen/framebuffer@9C000000/%s", name);
    int fd = open(path, O_RDONLY);
    if (fd < 0) { perror(path); exit(1); }
    if (read(fd, buf, size) != (ssize_t)size) { fprintf(stderr, "Invalid property: %s\n", name); exit(1); }
    close(fd);
}

int main(int argc, char **argv) {
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
    FILE *out = NULL;
    if (argc > 1) {
        out = fopen(argv[1], "wb");
        if (!out) { perror(argv[1]); return 1; }
        fprintf(out, "P6\n%u %u\n255\n", w / 4, h / 4);
    }
    uint32_t hash = 2166136261u;
    for (uint32_t y = 0; y < h; y += 4) {
        for (uint32_t x = 0; x < w; x += 4) {
            uint32_t p = pixels[y * (stride / 4) + x];
            unsigned char rgb[] = {p >> 16, p >> 8, p};
            for (unsigned c = 0; c < 3; c++) hash = (hash ^ rgb[c]) * 16777619u;
            if (out && fwrite(rgb, 1, 3, out) != 3) { perror("write snapshot"); return 1; }
        }
    }
    printf("sampled_rgb_fnv1a=%08x\n", hash);
    int error = out && fclose(out);
    munmap((void *)pixels, size);
    close(fd);
    return error ? 1 : 0;
}
