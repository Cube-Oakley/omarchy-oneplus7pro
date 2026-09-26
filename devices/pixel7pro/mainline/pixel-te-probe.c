// SPDX-License-Identifier: GPL-2.0-only
/* Bounded DECON TE-edge observer for the validated scanout17 handoff.
 * Events may be gated while DECON is idle; use active-frame measurements.
 * Uses cal_9845 DECON INT_EXTRA TE_RISE, not frame-done or a synthetic timer.
 * Restores both interrupt masks; changes no trigger, DMA or panel state.
 */
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/ktime.h>
#include <linux/module.h>
#include <linux/of_address.h>
#include <linux/of_irq.h>
#include <linux/platform_device.h>
#include <linux/workqueue.h>

static bool probe;
module_param(probe, bool, 0400);
static unsigned int seconds = 10;
module_param(seconds, uint, 0400);
static void __iomem *r;
static int irq;
static u32 saved_main, saved_extra;
static bool active;
static u64 count, first, last, min_ns = U64_MAX, max_ns;
static u64 bins[5];
static struct delayed_work stop_work;

static irqreturn_t te_irq(int number, void *data)
{
	u32 pending = readl(r + 0x74);
	u64 now, delta;

	if (!(pending & BIT(16)))
		return IRQ_NONE;
	writel(BIT(16), r + 0x74);
	readl(r + 0x74);
	now = ktime_get_ns();
	if (count) {
		delta = now - last;
		min_ns = min(min_ns, delta);
		max_ns = max(max_ns, delta);
		bins[delta < 7000000 ? 0 : delta < 10000000 ? 1 :
		     delta < 14000000 ? 2 : delta < 19000000 ? 3 : 4]++;
	} else {
		first = now;
	}
	last = now;
	count++;
	if (count > 20000)
		writel(0, r + 0x64);
	return IRQ_HANDLED;
}

static void stop(void)
{
	if (!active)
		return;
	writel(saved_main, r + 0x60);
	writel(saved_extra, r + 0x64);
	readl(r + 0x64);
	free_irq(irq, &active);
	writel(BIT(16), r + 0x74);
	active = false;
	pr_info("pixel-te: edges=%llu span_ns=%llu min_ns=%llu max_ns=%llu bins_lt7_lt10_lt14_lt19_ge19ms=%llu,%llu,%llu,%llu,%llu restored=%08x/%08x\n",
		count, last - first, count > 1 ? min_ns : 0, max_ns,
		bins[0], bins[1], bins[2], bins[3], bins[4],
		readl(r + 0x60), readl(r + 0x64));
}

static void stop_worker(struct work_struct *work)
{
	stop();
}

static int __init te_init(void)
{
	struct device_node *np;
	struct resource res;
	void __iomem *pmu;
	struct device *dev;
	bool valid;
	int ret;

	if (!probe || !seconds || seconds > 60 ||
	    !of_machine_is_compatible("google,GS201 CHEETAH"))
		return -EINVAL;
	dev = bus_find_device_by_name(&platform_bus_type, NULL, "pixel-scanout");
	if (!dev)
		return -ENODEV;
	valid = dev->driver && !strcmp(dev->driver->name, "pixel-scanout");
	put_device(dev);
	if (!valid)
		return -ENODEV;
	np = of_find_node_by_path("/drmdecon@0x1C240000");
	if (!np)
		return -ENODEV;
	valid = !of_address_to_resource(np, 0, &res) && res.start == 0x1c240000 &&
		resource_size(&res) == 0x6000;
	irq = of_irq_get_byname(np, "extra");
	of_node_put(np);
	if (!valid || irq <= 0)
		return -ENODEV;
	pmu = ioremap(0x18062000, PAGE_SIZE);
	if (!pmu)
		return -ENOMEM;
	valid = (readl(pmu + 0x204) & 1) && (readl(pmu + 0x284) & 1);
	iounmap(pmu);
	if (!valid)
		return -ENODEV;
	r = ioremap(0x1c240000, PAGE_SIZE);
	if (!r)
		return -ENOMEM;
	saved_main = readl(r + 0x60);
	saved_extra = readl(r + 0x64);
	ret = -EBUSY;
	if (saved_main != 0x3001 || saved_extra != 0x11)
		goto unmap;
	ret = request_irq(irq, te_irq, 0, "pixel-panel-te", &active);
	if (ret)
		goto unmap;
	INIT_DELAYED_WORK(&stop_work, stop_worker);
	active = true;
	writel(BIT(16), r + 0x74);
	writel(BIT(16), r + 0x64);
	writel(saved_main | BIT(4), r + 0x60);
	schedule_delayed_work(&stop_work, seconds * HZ);
	pr_info("pixel-te: observing %us irq=%d\n", seconds, irq);
	return 0;
unmap:
	iounmap(r);
	return ret;
}

static void __exit te_exit(void)
{
	cancel_delayed_work_sync(&stop_work);
	stop();
	iounmap(r);
}
module_init(te_init);
module_exit(te_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Bounded Pixel DECON panel TE observer");
