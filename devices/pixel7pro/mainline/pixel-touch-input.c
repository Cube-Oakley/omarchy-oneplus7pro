// SPDX-License-Identifier: GPL-2.0-only
/* Temporary cheetah touch probe. Only GET_APPLICATION_INFO and
 * GET_TOUCH_REPORT_CONFIG are sent; no firmware/configuration writes.
 * SPI reads clock 0xff as required by Google's Synaptics transport.
 * Development-only polling input driver. Restores pins on unload or timeout.
 */
#include <linux/delay.h>
#include <linux/io.h>
#include <linux/ioport.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_address.h>
#include <linux/input/mt.h>
#include <linux/kthread.h>
#include <linux/ktime.h>
#include <linux/unaligned.h>

static bool probe;
module_param(probe, bool, 0400);
MODULE_PARM_DESC(probe, "Explicit opt-in to bounded reset/read/restore probe");
static void __iomem *peri, *far, *hsi;
static const unsigned long bases[]={0x10c40000,0x180e0000,0x11840000};
static u32 con, dat, pud, rdat, hcon, hdat;
static int claimed;
static bool changed;
static struct input_dev *input;
static struct task_struct *worker;
static unsigned int seconds=300;
module_param(seconds, uint, 0400);
static unsigned int half_period_us=1;
module_param(half_period_us, uint, 0400);
static u64 transfer_ns, transfer_bytes, read_retries;
static void restore_pins(void);
static const u8 expected_config[128] = {
  0x10,8,0x1b,56,0x1e,8,0x17,8,0x18,8,4,1,6,4,7,4,
  8,16,9,16,10,16,11,8,12,8,0xd2,8,0xd3,8,0xd1,8,3,0
};
static void bits(void __iomem *r, u32 mask, u32 value)
{
    writel((readl(r) & ~mask) | (value & mask), r);
    readl(r);
}
static u8 transfer_byte(u8 tx)
{
    u8 v=0;
    for (int i=0;i<8;i++) {
        bits(peri+4, 3, (tx & (0x80 >> i)) ? 2 : 0);
        udelay(half_period_us);
        bits(peri+4, 1, 1); udelay(half_period_us);
        v=(v<<1)|((readl(peri+4)>>2)&1);
    }
    bits(peri+4, 1, 0);
    return v;
}
static void transfer(const u8 *tx, u8 *rx, unsigned int count)
{
    u64 start=ktime_get_ns();
    bits(peri+4,8,0);
    for (unsigned int i=0; i<count; i++) {
        u8 value = transfer_byte(tx ? tx[i] : 0xff);
        if (rx) rx[i] = value;
    }
    bits(peri+4,8,8);
    transfer_ns += ktime_get_ns()-start;
    transfer_bytes += count;
}
/* Vendor TCM v1 retries reads with a missing marker up to ten times,
 * separated by 5-10 ms. A low attention line alone does not guarantee that
 * the SPI response is ready. Never accept a packet without its framing.
 */
static int read_packet(u8 *buf, unsigned int count)
{
    for (int retry=0; retry<10; retry++) {
        if (readl(far+0x44)&0x80) return -EBUSY;
        transfer(NULL,buf,count);
        if (buf[0]==0xa5) return 0;
        read_retries++;
        pr_info_ratelimited("pixel-touch: read not ready len=%u prefix=%*ph retry=%d\n",
            count, min(count,4U),buf,retry+1);
        usleep_range(5000,10000);
    }
    return -EPROTO;
}
static int get_info(u8 cmd)
{
    u8 request[] = {cmd, 0, 0}, header[4], body[259];
    unsigned int len;
    int ret;
    if (cmd != 0x20 && cmd != 0x25) return -EINVAL;
    transfer(request, NULL, sizeof(request));
    /* Match the vendor TCM v1 polling response interval. The preceding
     * response's attention level can still be low immediately after a write;
     * it is not a completion event for this command. Only initialization
     * commands use this delay; touch report polling is unchanged.
     */
    msleep(10);
    for (int i=0; i<100; i++) {
        if (readl(far+0x44)&0x80) return -EBUSY;
        if (!(readl(far+0x24)&1)) break;
        if (i == 99) return -ETIMEDOUT;
        msleep(5);
    }
    ret=read_packet(header,sizeof(header));
    if (ret) return ret;
    len = header[2] | header[3]<<8;
    pr_info("pixel-touch-probe: command %02x header %*ph\n", cmd, 4, header);
    if (header[0] != 0xa5 || header[1] != 1 || len > 256) return -EPROTO;
    ret=read_packet(body,len+3);
    if (ret) return ret;
    if (body[0] != 0xa5 || body[1] != 3 || body[len+2] != 0x5a) return -EPROTO;
    print_hex_dump(KERN_INFO, "pixel-touch-probe: payload ", DUMP_PREFIX_OFFSET, 16, 1, body+2, len, false);
    if (cmd == 0x20 && (len != 46 || get_unaligned_le16(body+4) != 0 ||
        get_unaligned_le16(body+34) != 1439 || get_unaligned_le16(body+36) != 3119 ||
        get_unaligned_le16(body+38) != 10)) return -EPROTO;
    if (cmd == 0x25 && (len != sizeof(expected_config) ||
        memcmp(body+2, expected_config, sizeof(expected_config)))) return -EPROTO;
    return 0;
}
static int report_touch(const u8 *p, unsigned int len)
{
    unsigned long seen=0;
    unsigned int count;
    if (len < 11) return -EPROTO;
    count=p[10];
    if (count > 10 || len != 11+12*count) return -EPROTO;
    /* Validate complete packet before publishing any input events. */
    for (unsigned int n=0; n<count; n++) {
        const u8 *o=p+11+n*12;
        unsigned int id=o[0]&15;
        if (id >= 10 || (seen & BIT(id)) || get_unaligned_le16(o+1)>1439 ||
            get_unaligned_le16(o+3)>3119) return -EPROTO;
        seen |= BIT(id);
    }
    for (unsigned int n=0; n<count; n++) {
        const u8 *o=p+11+n*12;
        unsigned int id=o[0]&15, type=o[0]>>4;
        bool active=type==1 || type==2;
        input_mt_slot(input,id);
        input_mt_report_slot_state(input,MT_TOOL_FINGER,active);
        if (active) {
            input_report_abs(input,ABS_MT_POSITION_X,get_unaligned_le16(o+1));
            input_report_abs(input,ABS_MT_POSITION_Y,get_unaligned_le16(o+3));
            pr_info_ratelimited("pixel-touch: contact slot=%u x=%u y=%u\n",id,
                get_unaligned_le16(o+1),get_unaligned_le16(o+3));
        }
    }
    input_mt_sync_frame(input);
    input_sync(input);
    return 0;
}
static int poll_touch(void *unused)
{
    unsigned long deadline=jiffies+seconds*HZ;
    unsigned int reports=0;
    int ret=0;
    while (!kthread_should_stop() && (!seconds || time_before(jiffies,deadline))) {
        u8 header[4], body[259];
        unsigned int len;
        if (readl(far+0x44)&0x80) { ret=-EBUSY; break; }
        if (readl(far+0x24)&1) { msleep(8); continue; }
        ret=read_packet(header,4);
        if (ret) break;
        len=get_unaligned_le16(header+2);
        if (header[0]!=0xa5 || len>256) { ret=-EPROTO; break; }
        if (!len) { msleep(8); continue; }
        ret=read_packet(body,len+3);
        if (ret) break;
        if (body[0]!=0xa5 || body[1]!=3 || body[len+2]!=0x5a) {
            pr_err("pixel-touch: invalid body header=%*ph len=%u prefix=%*ph tail=%02x\n",
                4,header,len,min(len+3,4U),body,body[len+2]);
            ret=-EPROTO; break;
        }
        if (header[1]==0x11) {
            ret=report_touch(body+2,len);
            if (ret) {
                print_hex_dump(KERN_ERR,"pixel-touch: rejected ",DUMP_PREFIX_OFFSET,16,1,body+2,len,false);
                break;
            }
            reports++;
        } else {
            pr_info_ratelimited("pixel-touch: report=%02x len=%u\n",header[1],len);
            if (header[1]==0x10) { ret=-EPROTO; break; }
        }
        cond_resched();
    }
    for (int i=0;i<10;i++) {
        input_mt_slot(input,i);
        input_mt_report_slot_state(input,MT_TOOL_FINGER,false);
    }
    input_mt_sync_frame(input); input_sync(input);
    restore_pins();
    pr_info("pixel-touch: stopped reports=%u error=%d; pins restored\n",reports,ret);
    pr_info("pixel-touch: transfer bytes=%llu total_us=%llu half_period_us=%u\n",
        transfer_bytes, div_u64(transfer_ns,1000),half_period_us);
    pr_info("pixel-touch: read retries=%llu\n",read_retries);
    /* Keep task lifetime valid for module_exit's kthread_stop(). */
    while (!kthread_should_stop())
        msleep(100);
    return ret;
}
static int __init touch_probe_init(void)
{
    u8 reply[64];
    int ret=-ENODEV;
    if (half_period_us < 1 || half_period_us > 10 || (seconds && seconds < 10) || seconds > 600 || !probe || !of_machine_is_compatible("google,GS201 CHEETAH"))
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
    changed=true;
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
    if (ret) goto restore;
    input=input_allocate_device();
    if (!input) { ret=-ENOMEM; goto restore; }
    input->name="Pixel 7 Pro Synaptics S3908 (GPIO development)";
    input->phys="pixel-touch-gpio/input0";
    input->id.bustype=BUS_SPI;
    input_set_abs_params(input,ABS_MT_POSITION_X,0,1439,0,0);
    input_set_abs_params(input,ABS_MT_POSITION_Y,0,3119,0,0);
    ret=input_mt_init_slots(input,10,INPUT_MT_DIRECT|INPUT_MT_DROP_UNUSED);
    if (!ret) ret=input_register_device(input);
    if (ret) { input_free_device(input); input=NULL; goto restore; }
    worker=kthread_run(poll_touch,NULL,"pixel-touch");
    if (IS_ERR(worker)) {
        ret=PTR_ERR(worker); worker=NULL;
        input_unregister_device(input); input=NULL;
        goto restore;
    }
    pr_info("pixel-touch: physical input enabled for %u seconds\n",seconds);
    return 0;
restore:
    restore_pins();
done:
    if (peri) iounmap(peri);
    if (far) iounmap(far);
    if (hsi) iounmap(hsi);
    for(int i=0;i<claimed;i++) release_mem_region(bases[i],4096);
    return ret;
}
static void restore_pins(void)
{
    if (!changed) return;
    /* Return reset first, then GPIO inputs, before restoring data/pulls. */
    bits(peri+4,8,8); bits(peri+0x64,4,rdat);
    bits(peri,0xffff,con); bits(peri+4,0xf,dat); bits(peri+8,0xffff,pud);
    bits(hsi+0x20,0xf,hcon); bits(hsi+0x24,1,hdat);
    pr_info("pixel-touch-probe: restored SPI con=%08x dat=%08x reset=%08x AP con=%08x dat=%08x\n",
        readl(peri),readl(peri+4),readl(peri+0x64),readl(hsi+0x20),readl(hsi+0x24));
    changed=false;
}
static void __exit touch_probe_exit(void)
{
    if (worker) kthread_stop(worker);
    if (input) input_unregister_device(input);
    restore_pins();
    if (peri) iounmap(peri);
    if (far) iounmap(far);
    if (hsi) iounmap(hsi);
    for(int i=0;i<claimed;i++) release_mem_region(bases[i],4096);
}
module_init(touch_probe_init);
module_exit(touch_probe_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Pixel 7 Pro bounded GPIO touch input experiment");
