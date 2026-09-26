// SPDX-License-Identifier: GPL-2.0-only
/* Bounded S6E3HC4 HS/manual 60 -> 120 -> 60 experiment on scanout17.
 * No compositor may be running when loaded/unloaded. The DSIM transport and
 * correlated panel sequence follow Google's pinned display driver (see docs).
 * Changes no PLL, PHY, DSC, voltage, brightness, DMA or persistent storage.
 */
#include <linux/delay.h>
#include <linux/io.h>
#include <linux/iopoll.h>
#include <linux/module.h>
#include <linux/of_address.h>
#include <linux/platform_device.h>
#include <linux/workqueue.h>

static bool probe;
module_param(probe, bool, 0400);
static bool host_timing;
module_param(host_timing, bool, 0400);
static void __iomem *dsi, *decon;
static u32 saved_timer, saved_underrun, saved_te0;
static bool active;
static struct delayed_work restore_work;


static int wait_idle(void)
{
	u32 state;

	if ((readl(decon + 0x30) & 0x11) != 0x10)
		return -EBUSY;
	return readl_poll_timeout(decon + 0x20, state, state & BIT(5), 50, 100000);
}

static void queue_dcs(const u8 *data, unsigned int length)
{
	u32 payload;

	if (length == 2) {
		writel((data[1] << 16) | (data[0] << 8) | 0x15, dsi + 0x58);
		return;
	}
	for (unsigned int i = 0; i < length; i += 4) {
		payload = 0;
		for (unsigned int j = 0; j < 4 && i + j < length; j++)
			payload |= (u32)data[i + j] << (8 * j);
		writel(payload, dsi + 0x5c);
	}
	writel((length << 8) | 0x39, dsi + 0x58);
}
#define CMD(...) do { \
	const u8 bytes[] = { __VA_ARGS__ }; \
	queue_dcs(bytes, ARRAY_SIZE(bytes)); \
} while (0)

static int set_refresh(bool fast)
{
	u32 state, config = readl(dsi + 0x80);
	int ret = wait_idle();

	if (ret || config)
		return ret ?: -EBUSY;
	ret = readl_poll_timeout(dsi + 0x68, state,
		(state & 0x500) == 0x500, 50, 50000);
	if (ret)
		return ret;
	/* Nine headers, 32 padded payload bytes: one packet-go transaction. */
	writel(BIT(16), dsi + 0x80);
	CMD(0xf0, 0x5a, 0x5a);
	CMD(0xb9, fast ? 0x51 : 0x04);
	CMD(0xbd, 0x21, fast ? 0x01 : 0x81, 0x83, 0x03, 0x03);
	CMD(0xb0, 0x00, 0x1e, 0xbd);
	CMD(0xbd, 0x00, 0x00, 0x00, 0x02, 0x00, 0x06, 0x00, 0x16);
	CMD(0xbd, 0x21);
	CMD(0x60, fast ? 0x00 : 0x01);
	CMD(0xf7, 0x0f);
	CMD(0xf0, 0xa5, 0xa5);
	writel(BIT(28) | BIT(29), dsi + 0x50);
	writel(BIT(16) | BIT(17), dsi + 0x80);
	ret = readl_poll_timeout(dsi + 0x68, state,
		(state & 0x500) == 0x500, 50, 100000);
	writel(config, dsi + 0x80);
	if (ret)
		pr_err("pixel-refresh: FIFO timeout %08x\n", state);
	if (!ret && host_timing) {
		/* HS clock 1346 MHz, 4 lanes, RGB888 compressed 3:1, vendor
		 * te_var=1 and te_idle_us=350. Guards check actual PLL first.
		 */
		u64 wclk = 1346000000ULL / 16;
		u64 max_ns = 100000000000ULL / (120 * 101) - 350000;
		u64 min_ns = (3120ULL * (480 * 3 + 7)) * 1000000000ULL / (8 * wclk);
		u32 underrun = DIV_ROUND_UP_ULL((max_ns - min_ns) * wclk / 1000000000, 100);
		u32 protect = 1346 * 95 * 100 / 120 / 16;
		u32 timeout = 1346 * 110 * 100 / 120 / 16;

		writel(fast ? underrun : saved_underrun, dsi + 0x34);
		writel(fast ? 28 : saved_te0, dsi + 0x84);
		writel(fast ? (protect << 16) | timeout : saved_timer, dsi + 0x88);
	}
	pr_info("pixel-refresh: requested=%u ret=%d host=%u timer=%08x underrun=%08x\n",
		fast ? 120 : 60, ret, host_timing, readl(dsi + 0x88), readl(dsi + 0x34));
	return ret;
}

static void restore(struct work_struct *unused)
{
	if (!active)
		return;
	if (set_refresh(false)) {
		pr_err("pixel-refresh: %s failed; stop testing and RAM reboot\n", __func__);
		return;
	}
	active = false;
}

static int __init refresh_init(void)
{
	struct device_node *np;
	struct resource res;
	struct device *dev;
	void __iomem *pmu, *phy;
	bool valid;
	int ret = -ENODEV;

	if (!probe || !of_machine_is_compatible("google,GS201 CHEETAH"))
		return -EINVAL;
	dev = bus_find_device_by_name(&platform_bus_type, NULL, "pixel-scanout");
	if (!dev)
		return -ENODEV;
	valid = dev->driver && !strcmp(dev->driver->name, "pixel-scanout");
	put_device(dev);
	if (!valid)
		return -ENODEV;
	np = of_find_node_by_path("/drmdsim@0x1C2C0000");
	if (!np)
		return -ENODEV;
	valid = !of_address_to_resource(np, 0, &res) && res.start == 0x1c2c0000 &&
		resource_size(&res) == 0x300;
	valid = valid && !of_address_to_resource(np, 1, &res) && res.start == 0x1c2e0100;
	of_node_put(np);
	if (!valid)
		return -ENODEV;
	pmu = ioremap(0x18062000, PAGE_SIZE);
	if (!pmu)
		return -ENOMEM;
	valid = (readl(pmu + 0x204) & 1) && (readl(pmu + 0x284) & 1);
	iounmap(pmu);
	if (!valid)
		return -ENODEV;
	dsi = ioremap(0x1c2c0000, PAGE_SIZE);
	decon = ioremap(0x1c240000, PAGE_SIZE);
	phy = ioremap(0x1c2e0100, 0x100);
	if (!dsi || !decon || !phy) {
		ret = -ENOMEM;
		if (phy)
			iounmap(phy);
		goto fail;
	}
	/* P=2, M=219, S=2, K=0x1355 from the pinned 1346 MHz mode. */
	valid = (readl(phy) & 0x173f) == 0x1202 &&
		(readl(phy + 4) & 0xffff) == 0x1355 &&
		(readl(phy + 8) & 0x3ff) == 0xdb;
	iounmap(phy);
	if (!valid || readl(dsi) != 0x02060000 || readl(dsi + 0x4c) != 0x04887cff ||
	    readl(dsi + 0x80) || wait_idle())
		goto fail;
	saved_te0 = readl(dsi + 0x84);
	saved_timer = readl(dsi + 0x88);
	saved_underrun = readl(dsi + 0x34);
	if (saved_underrun != 7945 || saved_timer != 0x33eb3b26 || saved_te0 != 86)
		goto fail;
	pr_info("pixel-refresh: baseline timer=%08x underrun=%08x te0=%08x\n", saved_timer, saved_underrun, saved_te0);
	/* The read-only probe must first establish the HS/manual/non-HBM
	 * baseline; this experiment deliberately does not alter operation mode.
	 */
	INIT_DELAYED_WORK(&restore_work, restore);
	active = true;
	ret = set_refresh(true);
	if (ret) {
		restore(NULL);
		goto fail;
	}
	schedule_delayed_work(&restore_work, 60 * HZ);
	return 0;
fail:
	if (dsi)
		iounmap(dsi);
	if (decon)
		iounmap(decon);
	return ret;
}

static void __exit refresh_exit(void)
{
	cancel_delayed_work_sync(&restore_work);
	restore(NULL);
	iounmap(dsi);
	iounmap(decon);
}
module_init(refresh_init);
module_exit(refresh_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Bounded Pixel 120 Hz panel experiment with 60 Hz restore");
