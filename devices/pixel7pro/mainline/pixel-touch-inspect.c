// SPDX-License-Identifier: GPL-2.0-only
/* Read-only GS201 touch pin inventory. No SPI transfers or register writes.
 * Offsets from Google's pinctrl-gs201.c; wiring from saved cheetah live DT.
 */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

static void fail(const char *s) { perror(s); exit(1); }
static void bank(int fd, unsigned long base, unsigned off, const char *name)
{
    char path[160]; unsigned char reg[16];
    snprintf(path,sizeof(path),"/sys/firmware/devicetree/base/pinctrl@%lX/reg",base);
    int dt=open(path,O_RDONLY);
    if (dt<0) fail(path);
    ssize_t len=read(dt,reg,sizeof(reg));
    if (len!=12 && len!=16) { fprintf(stderr,"Unexpected DT reg size %zd\n",len); exit(1); }
    close(dt);
    uint64_t address=0, size=0;
    for (int i=0;i<8;i++) address=(address<<8)|reg[i];
    for (int i=8;i<len;i++) size=(size<<8)|reg[i];
    if (address!=base || size!=4096) { fprintf(stderr,"Unexpected DT range\n"); exit(1); }
    printf("Reading %s at %08lx+%x\n",name,base,off); fflush(stdout);
    void *map=mmap(NULL,4096,PROT_READ,MAP_SHARED,fd,base);
    if(map==MAP_FAILED) fail("mmap GPIO");
    volatile const uint32_t *r=(volatile const uint32_t *)((char *)map+off);
    printf("%s CON=%08x DAT=%08x PUD=%08x DRV=%08x\n",name,r[0],r[1],r[2],r[3]);
    munmap(map,4096);
}
int main(void)
{
    char compat[256]={0};
    int f=open("/sys/firmware/devicetree/base/compatible",O_RDONLY);
    if(f<0) fail("compatible");
    ssize_t n=read(f,compat,sizeof(compat)-1); close(f);
    if(n<0 || strcmp(compat,"google,GS201 CHEETAH")) {
        fprintf(stderr,"Expected verified cheetah handoff\n"); return 1;
    }
    int fd=open("/dev/mem",O_RDONLY|O_SYNC);
    if(fd<0) fail("/dev/mem");
    bank(fd,0x180e0000,0x20,"gpa7-touch-irq");
    bank(fd,0x180e0000,0x40,"gpa8-aoc-ack");
    bank(fd,0x10c40000,0x00,"gpp20-touch-spi");
    bank(fd,0x10c40000,0x60,"gpp23-touch-reset");
    bank(fd,0x11840000,0x20,"gph1-ap-aoc-select");
    close(fd);
    return 0;
}
