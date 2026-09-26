// SPDX-License-Identifier: GPL-2.0-only
/* Bounded native DMA scanout test on the validated cheetah ABL handoff.
 * Allocates one buffer through dma_alloc_wc with a 32-bit mask; changes only
 * DPP0's RGB base and the validated retained refresh/IRQ registers. The original
 * ABL buffer is restored before freeing DMA memory. Userspace must stop the
 * compositor and keep it stopped until this module is unloaded. No IOMMU,
 * panel, clock, power, storage or display-mode changes.
 * Register definitions: Google display 0137241105270acf53c329e899ea9c4b6b1c8e66,
 * samsung/cal_9845/regs-decon.h and decon_reg.c.
 */
#include <linux/completion.h>
#include <linux/dma-mapping.h>
#include <linux/interrupt.h>
#include <linux/iopoll.h>
#include <linux/io.h>
#include <linux/ktime.h>
#include <linux/module.h>
#include <linux/of_address.h>
#include <linux/of_irq.h>
#include <linux/of_platform.h>
#include <linux/platform_device.h>
#include <linux/workqueue.h>

#define INT_EN 0x60
#define INT_PEND 0x70
#define FRAME_START BIT(12)
#define FRAME_DONE BIT(13)
#define FRAME_MASK (FRAME_START | FRAME_DONE)

static bool observe;
module_param(observe, bool, 0400);
static unsigned int seconds = 15;
module_param(seconds, uint, 0400);

#define FB_BYTES PAGE_ALIGN(1440 * 3120 * 4)
#define ORIGINAL_FB 0xfac00000U
static void __iomem *regs, *rdma;
static struct platform_device *alloc_dev;
static void *buffer;
static dma_addr_t buffer_dma;
static bool switched;
static DECLARE_COMPLETION(frame_complete);
static int irq_start, irq_done;
static u32 saved_enable;
static DEFINE_SPINLOCK(stats_lock);
static bool active;
static u64 starts, dones, pairs, total_ns, max_ns, last_start, unpaired;
static u64 first_ns, last_ns;
static struct delayed_work stop_work;

static irqreturn_t frame_irq(int irq, void *cookie)
{
	u32 bit = irq == irq_start ? FRAME_START : FRAME_DONE;
	unsigned long flags;
	u64 now, delta;

	if (!(readl(regs + INT_PEND) & bit))
		return IRQ_NONE;
	writel(bit, regs + INT_PEND);
	/* Flush the W1C acknowledgement before returning to the GIC. */
	readl(regs + INT_PEND);
	now = ktime_get_ns();
	spin_lock_irqsave(&stats_lock, flags);
	if (!first_ns)
		first_ns = now;
	last_ns = now;
	if (bit == FRAME_START) {
		starts++;
		if (last_start)
			unpaired++;
		last_start = now;
	} else {
		dones++;
		complete(&frame_complete);
		if (last_start) {
			delta = now - last_start;
			pairs++;
			total_ns += delta;
			max_ns = max(max_ns, delta);
			last_start = 0;
		} else {
			unpaired++;
		}
	}
	/* Bound an unexpected interrupt storm without logging in hard IRQ. */
	if (starts + dones > 20000)
		writel(saved_enable, regs + INT_EN);
	spin_unlock_irqrestore(&stats_lock, flags);
	return IRQ_HANDLED;
}

static int scanout_address(u32 addr)
{
	u32 trigger = readl(regs + 0x30), status;
	int ret;

	if (!(trigger & BIT(4)))
		return -EBUSY;
	ret = readl_poll_timeout(regs + 0x20, status, status & BIT(5), 50, 100000);
	if (ret)
		return ret;
	synchronize_irq(irq_done);
	reinit_completion(&frame_complete);
	/* DMA allocation is WC; complete stores before publishing its address. */
	wmb();
	writel(addr, rdma + 0x40);
	writel(readl(regs + 0x50) | 0x3f, regs + 0x50);
	writel(readl(regs + 0x20) | 3, regs + 0x20);
	writel(readl(regs + 0x50) | 0x80100000, regs + 0x50);
	writel((trigger & ~BIT(4)) | 1, regs + 0x30);
	ret = wait_for_completion_timeout(&frame_complete, msecs_to_jiffies(100)) ? 0 : -ETIMEDOUT;
	writel(trigger, regs + 0x30);
	if (ret)
		return ret;
	ret = readl_poll_timeout(regs + 0x20, status, status & BIT(5), 50, 100000);
	if (ret || readl(rdma + 0x440) != addr)
		return -EIO;
	pr_info("pixel-dma-scanout: frame completed at DMA %08x active_shadow=%08x\n",
		addr, readl(rdma + 0x440));
	return 0;
}

static void stop_observation(void)
{
	if (!active)
		return;
	if (switched) {
		if (scanout_address(ORIGINAL_FB))
			pr_err("pixel-dma-scanout: restore NOT confirmed; retaining allocation until reboot\n");
		else
			switched = false;
	}
	writel(saved_enable, regs + INT_EN);
	readl(regs + INT_EN);
	synchronize_irq(irq_start);
	synchronize_irq(irq_done);
	free_irq(irq_done, &active);
	free_irq(irq_start, &active);
	/* Discard only this observer's pending sources, with global IRQ off. */
	writel(FRAME_MASK, regs + INT_PEND);
	active = false;
	pr_info("pixel-dma-scanout: stopped starts=%llu dones=%llu pairs=%llu unpaired=%llu transfer_total_ns=%llu transfer_max_ns=%llu observation_ns=%llu restored_enable=%08x\n",
		starts, dones, pairs, unpaired, total_ns, max_ns,
		last_ns - first_ns, readl(regs + INT_EN));
}

static void stop_observation_work(struct work_struct *work)
{
	stop_observation();
}

static int __init pixel_decon_irq_init(void)
{
	struct device_node *np;
	struct platform_device *pdev;
	struct device *bridge;
	struct resource res;
	void __iomem *pmu, *dma, *mmu;
	u32 irq_cells[6];
	bool valid;
	int ret;

	if (!observe || seconds < 1 || seconds > 60 ||
	    !of_machine_is_compatible("google,GS201 CHEETAH"))
		return -EINVAL;
	bridge = bus_find_device_by_name(&platform_bus_type, NULL, "pixel-handoff");
	if (!bridge)
		return -ENODEV;
	valid = bridge->driver && !strcmp(bridge->driver->name, "pixel-handoff");
	put_device(bridge);
	if (!valid)
		return -ENODEV;
	np = of_find_node_by_path("/drmdecon@0x1C240000");
	if (!np)
		return -ENODEV;
	ret = -ENODEV;
	pdev = of_find_device_by_node(np);
	valid = !pdev || !pdev->dev.driver;
	if (pdev)
		put_device(&pdev->dev);
	if (!valid || of_address_to_resource(np, 0, &res) ||
	    res.start != 0x1c240000 || resource_size(&res) != 0x6000 ||
	    of_property_read_u32_array(np, "interrupts", irq_cells, 6) ||
	    irq_cells[0] || irq_cells[1] != 241 || irq_cells[2] != 4 ||
	    irq_cells[3] || irq_cells[4] != 240 || irq_cells[5] != 4)
		goto put_node;
	irq_start = of_irq_get_byname(np, "frame_start");
	irq_done = of_irq_get_byname(np, "frame_done");
	if (irq_start <= 0 || irq_done <= 0 || irq_start == irq_done)
		goto put_node;
	of_node_put(np);
	pmu = ioremap(0x18062000, PAGE_SIZE);
	if (!pmu)
		return -ENOMEM;
	valid = (readl(pmu + 0x204) & 1) && (readl(pmu + 0x284) & 1);
	iounmap(pmu);
	if (!valid)
		return -ENODEV;
	/* Hardware-identified v8.1 VM layout, measured disabled on image D.
	 * Refuse an enabled translation unit; no bypass or page-table writes.
	 */
	mmu = ioremap(0x1c100000, 0x10000);
	if (!mmu)
		return -ENOMEM;
	valid = readl(mmu + 0x34) == 0x80200001 &&
		readl(mmu + 0x874) == 0x0000e0a1 &&
		readl(mmu) == 0 && readl(mmu + 0x8000) == 0 &&
		readl(mmu + 0x800c) == 0;
	iounmap(mmu);
	if (!valid)
		return -ENODEV;
	alloc_dev = platform_device_register_simple("pixel-dma-scanout-probe", -1, NULL, 0);
	if (IS_ERR(alloc_dev))
		return PTR_ERR(alloc_dev);
	alloc_dev->dev.dma_mask = &alloc_dev->dev.coherent_dma_mask;
	ret = dma_set_mask_and_coherent(&alloc_dev->dev, DMA_BIT_MASK(32));
	if (ret)
		goto release_device;
	buffer = dma_alloc_wc(&alloc_dev->dev, FB_BYTES, &buffer_dma, GFP_KERNEL);
	if (!buffer) {
		ret = -ENOMEM;
		goto release_device;
	}
	if (upper_32_bits(buffer_dma + FB_BYTES - 1)) {
		ret = -ERANGE;
		goto free_buffer;
	}
	pr_info("pixel-dma-scanout: allocated %lu bytes DMA=%pad\n",
		(unsigned long)FB_BYTES, &buffer_dma);
	/* Immutable opaque RGB bars, white checkerboard and a dark border. */
	for (unsigned int y = 0; y < 3120; y++) {
		for (unsigned int x = 0; x < 1440; x++) {
			u32 color = x < 480 ? 0xffff0000 : x < 960 ? 0xff00ff00 : 0xff0000ff;

			if (y > 2200)
				color = ((x / 60 + y / 60) & 1) ? 0xffffffff : 0xff181818;
			if (x < 24 || x >= 1416 || y < 24 || y >= 3096)
				color = 0xff181818;
			((__le32 *)buffer)[y * 1440 + x] = cpu_to_le32(color);
		}
	}
	regs = ioremap(0x1c240000, PAGE_SIZE);
	dma = ioremap(0x1c0b0000, PAGE_SIZE);
	if (!regs || !dma) {
		ret = -ENOMEM;
		goto unmap_dma;
	}
	saved_enable = readl(regs + INT_EN);
	valid = saved_enable == FRAME_MASK &&
		(readl(regs + 0x20) & BIT(8)) &&
		(readl(regs + 0x30) & 0x11) == 0x10 &&
		readl(dma + 0x40) == 0xfac00000 &&
		readl(dma + 0x440) == 0xfac00000 &&
		readl(dma + 0x408) == 0xff400000 &&
		!readl(dma + 0x414) && !readl(dma + 0x450) &&
		readl(dma + 0x410) == 0x0c3005a0;
	/* The retained refresh momentarily changes the trigger; retry loading
	 * only after stopping animation if this conservative guard rejects it.
	 */
	ret = -EBUSY;
	if (!valid)
		goto unmap_dma;
	rdma = dma;
	ret = request_irq(irq_start, frame_irq, 0, "pixel-decon-start", &active);
	if (ret)
		goto unmap_dma;
	ret = request_irq(irq_done, frame_irq, 0, "pixel-decon-done", &active);
	if (ret) {
		free_irq(irq_start, &active);
		goto unmap_dma;
	}
	INIT_DELAYED_WORK(&stop_work, stop_observation_work);
	active = true;
	writel(FRAME_MASK, regs + INT_PEND);
	writel(FRAME_MASK | BIT(0), regs + INT_EN);
	readl(regs + INT_EN);
	switched = true;
	ret = scanout_address(lower_32_bits(buffer_dma));
	if (ret) {
		pr_err("pixel-dma-scanout: test failed %d; restoring original\n", ret);
		stop_observation();
		goto unmap_dma;
	}
	schedule_delayed_work(&stop_work, seconds * HZ);
	pr_info("pixel-dma-scanout: observing %us start_irq=%d done_irq=%d saved_enable=%08x\n",
		seconds, irq_start, irq_done, saved_enable);
	return 0;

unmap_dma:
	if (dma)
		iounmap(dma);
	if (regs)
		iounmap(regs);
free_buffer:
	if (!switched)
		dma_free_wc(&alloc_dev->dev, FB_BYTES, buffer, buffer_dma);
release_device:
	if (!switched)
		platform_device_unregister(alloc_dev);
	return ret;
put_node:
	of_node_put(np);
	return ret;
}

static void __exit pixel_decon_irq_exit(void)
{
	cancel_delayed_work_sync(&stop_work);
	stop_observation();
	iounmap(regs);
	iounmap(rdma);
	if (!switched) {
		dma_free_wc(&alloc_dev->dev, FB_BYTES, buffer, buffer_dma);
		platform_device_unregister(alloc_dev);
	}
}
module_init(pixel_decon_irq_init);
module_exit(pixel_decon_irq_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Bounded Pixel native DMA scanout and restore test");
