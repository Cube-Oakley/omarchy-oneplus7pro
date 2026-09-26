// SPDX-License-Identifier: GPL-2.0-only
/* Temporary cheetah touch probe. Only GET_APPLICATION_INFO and
 * GET_TOUCH_REPORT_CONFIG are sent; no firmware/configuration writes.
 * SPI reads clock 0xff as required by Google's Synaptics transport.
 * Pin state is restored before init returns, including the inherited reset.
 */
#include <linux/delay.h>
#include <linux/io.h>
#include <linux/ioport.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_address.h>

static bool probe;
module_param(probe, bool, 0400);
MODULE_PARM_DESC(probe, "Explicit opt-in to bounded reset/read/restore probe");
static void __iomem *peri, *far, *hsi;
static void bits(void __iomem *r, u32 mask, u32 value)
{
    writel((readl(r) & ~mask) | (value & mask), r);
    readl(r);
}
static u8 transfer_byte(u8 tx)
{
    u8 v=0;
    for (int i=0;i<8;i++) {
        bits(peri+4, 1, 0);
        bits(peri+4, 2, (tx & (0x80 >> i)) ? 2 : 0); udelay(5);
        bits(peri+4, 1, 1); udelay(5);
        v=(v<<1)|((readl(peri+4)>>2)&1);
    }
    bits(peri+4, 1, 0);
    return v;
}
static void transfer(const u8 *tx, u8 *rx, unsigned int count)
{
    bits(peri+4,8,0);
    for (unsigned int i=0; i<count; i++) {
        u8 value = transfer_byte(tx ? tx[i] : 0xff);
        if (rx) rx[i] = value;
    }
    bits(peri+4,8,8);
}
static int get_info(u8 cmd)
{
    u8 request[] = {cmd, 0, 0}, header[4], body[259];
    unsigned int len;
    if (cmd != 0x20 && cmd != 0x25) return -EINVAL;
    transfer(request, NULL, sizeof(request));
    for (int i=0; i<100; i++) {
        if (readl(far+0x44)&0x80) return -EBUSY;
        if (!(readl(far+0x24)&1)) break;
        if (i == 99) return -ETIMEDOUT;
        msleep(5);
    }
    transfer(NULL, header, sizeof(header));
    len = header[2] | header[3]<<8;
    pr_info("pixel-touch-probe: command %02x header %*ph\n", cmd, 4, header);
    if (header[0] != 0xa5 || header[1] != 1 || len > 256) return -EPROTO;
    transfer(NULL, body, len+3);
    if (body[0] != 0xa5 || body[1] != 3 || body[len+2] != 0x5a) return -EPROTO;
    print_hex_dump(KERN_INFO, "pixel-touch-probe: payload ", DUMP_PREFIX_OFFSET, 16, 1, body+2, len, false);
    return 0;
}
static int __init touch_probe_init(void)
{
    static const unsigned long bases[]={0x10c40000,0x180e0000,0x11840000};
    u32 con, dat, pud, rdat, hcon, hdat;
    u8 reply[64];
    int claimed=0, ret=-ENODEV;
    if (!probe || !of_machine_is_compatible("google,GS201 CHEETAH"))
        return -EINVAL;
    for (int i=0;i<3;i++) {
        char path[48];
        struct device_node *node;
        struct resource resource;
        int err;
        snprintf(path, sizeof(path), "/pinctrl@%lX", bases[i]);
        node = of_find_node_by_path(path);
        if (!node)
            goto done;
        err = of_address_to_resource(node, 0, &resource);
        of_node_put(node);
        if (err || resource.start != bases[i] || resource_size(&resource) != 4096)
            goto done;
        if (!request_mem_region(bases[i],4096,"pixel-touch-gpio-probe"))
            goto done;
        claimed++;
    }
    peri=ioremap(bases[0],4096); far=ioremap(bases[1],4096); hsi=ioremap(bases[2],4096);
    if (!peri || !far || !hsi) goto done;
    con=readl(peri); dat=readl(peri+4); pud=readl(peri+8);
    rdat=readl(peri+0x64); hcon=readl(hsi+0x20); hdat=readl(hsi+0x24);
    pr_info("pixel-touch-probe: SPI con=%08x dat=%08x reset con=%08x dat=%08x AP con=%08x dat=%08x ACK=%08x IRQ=%08x\n",
        con,dat,readl(peri+0x60),rdat,hcon,hdat,readl(far+0x44),readl(far+0x24));
    /* Require exactly the inspected unbound bootloader state. Never steal a bus. */
    if ((con&0xffff) || (dat&8)!=8 || (readl(peri+0x60)&0xf00)!=0x100 ||
        (rdat&4) || (hcon&0xf) || (hdat&1) || (readl(far+0x44)&0x80)) {
        pr_err("pixel-touch-probe: handoff differs, refusing writes\n"); goto done;
    }
    /* TBN_BUS_OWNER_AP=0, with aoc2ap low as acknowledgement. */
    bits(hsi+0x24,1,0); bits(hsi+0x20,0xf,1);
    if (readl(far+0x44)&0x80) { ret=-EBUSY; goto restore; }
    /* CS inactive, MOSI high (read filler), SCLK mode-0 low; MISO input. */
    bits(peri+4,0xf,0xa); bits(peri+8,0xffff,0x100);
    bits(peri,0xffff,0x1011);
    /* Bootloader already holds reset low. Use stock 20/200ms reset timings. */
    msleep(20); bits(peri+0x64,4,4); msleep(200);
    pr_info("pixel-touch-probe: after reset IRQ=%08x ACK=%08x\n",readl(far+0x24),readl(far+0x44));
    if (readl(far+0x44)&0x80) { ret=-EBUSY; goto restore; }
    bits(peri+4,8,0);
    for (int i=0;i<sizeof(reply);i++) reply[i]=transfer_byte(0xff);
    bits(peri+4,8,8);
    pr_info("pixel-touch-probe: startup reply %*ph\n",(int)sizeof(reply),reply);
    if (reply[0] != 0xa5 || reply[1] != 0x10 || reply[2] != 24 ||
        reply[3] != 0 || reply[4] != 1 || reply[5] != 1 || reply[28] != 0x5a) {
        ret=-EPROTO; goto restore;
    }
    ret=get_info(0x20);
    if (!ret) ret=get_info(0x25);
restore:
    /* Return reset first, then GPIO inputs, before restoring data/pulls. */
    bits(peri+4,8,8); bits(peri+0x64,4,rdat);
    bits(peri,0xffff,con); bits(peri+4,0xf,dat); bits(peri+8,0xffff,pud);
    bits(hsi+0x20,0xf,hcon); bits(hsi+0x24,1,hdat);
    pr_info("pixel-touch-probe: restored SPI con=%08x dat=%08x reset=%08x AP con=%08x dat=%08x\n",
        readl(peri),readl(peri+4),readl(peri+0x64),readl(hsi+0x20),readl(hsi+0x24));
done:
    if (peri)
        iounmap(peri);
    if (far)
        iounmap(far);
    if (hsi)
        iounmap(hsi);
    for(int i=0;i<claimed;i++) release_mem_region(bases[i],4096);
    return ret;
}
static void __exit touch_probe_exit(void) {}
module_init(touch_probe_init);
module_exit(touch_probe_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Bounded Pixel 7 Pro touch startup read and GPIO restore probe");
