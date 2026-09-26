// SPDX-License-Identifier: GPL-2.0-only
/* Bounded DECON0 interrupt observation on the validated cheetah ABL handoff.
 * Only INT_EN and W1C frame-start/frame-done pending bits are written. No
 * scanout address, mode, trigger, clock, power or IOMMU programming occurs.
 * Register definitions: Google display 0137241105270acf53c329e899ea9c4b6b1c8e66,
 * samsung/cal_9845/regs-decon.h and decon_reg.c.
 */
#include <linux/interrupt.h>
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
static unsigned int seconds = 30;
module_param(seconds, uint, 0400);

static void __iomem *regs;
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

static void stop_observation(void)
{
	if (!active)
		return;
	writel(saved_enable, regs + INT_EN);
	readl(regs + INT_EN);
	synchronize_irq(irq_start);
	synchronize_irq(irq_done);
	free_irq(irq_done, &active);
	free_irq(irq_start, &active);
	/* Discard only this observer's pending sources, with global IRQ off. */
	writel(FRAME_MASK, regs + INT_PEND);
	active = false;
	pr_info("pixel-decon-irq: stopped starts=%llu dones=%llu pairs=%llu unpaired=%llu transfer_total_ns=%llu transfer_max_ns=%llu observation_ns=%llu restored_enable=%08x\n",
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
	void __iomem *pmu, *dma;
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
		readl(dma + 0x410) == 0x0c3005a0;
	/* The retained refresh momentarily changes the trigger; retry loading
	 * only after stopping animation if this conservative guard rejects it.
	 */
	ret = -EBUSY;
	if (!valid)
		goto unmap_dma;
	iounmap(dma);
	ret = request_irq(irq_start, frame_irq, 0, "pixel-decon-start", &active);
	if (ret)
		goto unmap_regs;
	ret = request_irq(irq_done, frame_irq, 0, "pixel-decon-done", &active);
	if (ret) {
		free_irq(irq_start, &active);
		goto unmap_regs;
	}
	INIT_DELAYED_WORK(&stop_work, stop_observation_work);
	active = true;
	writel(FRAME_MASK, regs + INT_PEND);
	writel(FRAME_MASK | BIT(0), regs + INT_EN);
	readl(regs + INT_EN);
	schedule_delayed_work(&stop_work, seconds * HZ);
	pr_info("pixel-decon-irq: observing %us start_irq=%d done_irq=%d saved_enable=%08x\n",
		seconds, irq_start, irq_done, saved_enable);
	return 0;

unmap_dma:
	if (dma)
		iounmap(dma);
unmap_regs:
	if (regs)
		iounmap(regs);
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
}
module_init(pixel_decon_irq_init);
module_exit(pixel_decon_irq_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Bounded Pixel retained DECON frame interrupt observer");
