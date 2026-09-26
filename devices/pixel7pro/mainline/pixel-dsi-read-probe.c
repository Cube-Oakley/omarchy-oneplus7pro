// SPDX-License-Identifier: GPL-2.0-only
/* Bounded DCS read transport on cheetah's retained DSIM0. Pause the compositor
 * first. Optional vendor reads unlock/relock F0 only; no panel configuration,
 * reset, clock/PLL, PHY, power or DMA programming.
 * Packet layout and FIFO polling follow Google's pinned cal_9845 DSIM code.
 */
#include <linux/io.h>
#include <linux/iopoll.h>
#include <linux/module.h>
#include <linux/of_address.h>
#include <linux/platform_device.h>

static bool probe;
module_param(probe, bool, 0400);
static bool vendor;
module_param(vendor, bool, 0400);
static void __iomem *dsi;

static int vendor_key(bool unlock)
{
	u32 state;
	int ret;

	ret = readl_poll_timeout(dsi + 0x68, state,
		(state & (BIT(10) | BIT(8))) == (BIT(10) | BIT(8)), 50, 50000);
	if (ret)
		return ret;
	writel(unlock ? 0x005a5af0 : 0x00a5a5f0, dsi + 0x5c);
	writel((3 << 8) | 0x39, dsi + 0x58);
	return readl_poll_timeout(dsi + 0x68, state,
		(state & (BIT(10) | BIT(8))) == (BIT(10) | BIT(8)), 50, 50000);
}

static int read_dcs(u8 command, unsigned int length)
{
	u8 data[16] = { 0 };
	u32 value, header, count, type;
	int ret;

	if (!length || length > sizeof(data))
		return -EINVAL;
	/* Never consume a pre-existing response belonging to another owner. */
	if (!(readl(dsi + 0x68) & BIT(12)))
		return -EBUSY;
	ret = readl_poll_timeout(dsi + 0x68, value,
		(value & (BIT(10) | BIT(8))) == (BIT(10) | BIT(8)), 50, 50000);
	if (ret)
		return ret;
	writel(BIT(18) | BIT(28), dsi + 0x50);
	/* Set maximum return packet size, followed by DCS_READ with BTA. */
	writel((length << 8) | 0x37, dsi + 0x58);
	writel(BIT(24) | (command << 8) | 0x06, dsi + 0x58);
	ret = readl_poll_timeout(dsi + 0x50, value, value & BIT(18), 50, 100000);
	if (ret) {
		pr_err("pixel-dsi: read %02x timeout irq=%08x fifo=%08x status=%08x\n",
			command, value, readl(dsi + 0x68), readl(dsi + 0x8c));
		return ret;
	}
	if (readl(dsi + 0x68) & BIT(12))
		return -ENODATA;
	header = readl(dsi + 0x60);
	type = header & 0x3f;
	if (type == 0x21 || type == 0x22) {
		count = type == 0x21 ? 1 : 2;
		data[0] = header >> 8;
		data[1] = header >> 16;
	} else if (type == 0x1c) {
		count = (header >> 8) & 0xffff;
		if (!count || count > sizeof(data))
			return -EMSGSIZE;
		for (unsigned int i = 0; i < count; i++) {
			if (!(i % 4)) {
				if (readl(dsi + 0x68) & BIT(12))
					return -ENODATA;
				value = readl(dsi + 0x60);
			}
			data[i] = value >> (8 * (i % 4));
		}
	} else {
		pr_err("pixel-dsi: read %02x unexpected response %08x\n", command, header);
		return -EPROTO;
	}
	if (!(readl(dsi + 0x68) & BIT(12))) {
		/* The vendor host drains trailers with a bounded loop. */
		for (unsigned int i = 0; i < 4 && !(readl(dsi + 0x68) & BIT(12)); i++)
			pr_info("pixel-dsi: RX trailer %08x\n", readl(dsi + 0x60));
		if (!(readl(dsi + 0x68) & BIT(12)))
			return -EOVERFLOW;
	}
	writel(BIT(18) | BIT(28), dsi + 0x50);
	pr_info("pixel-dsi: DCS %02x response=%08x bytes=%u data=%*ph\n",
		command, header, count, count, data);
	return count == length ? 0 : -EMSGSIZE;
}

static int __init dsi_probe_init(void)
{
	struct device_node *np;
	struct resource res;
	struct device *dev;
	void __iomem *pmu = NULL, *decon = NULL, *phy;
	bool valid;
	u32 state;
	int ret = -ENODEV;
	const u8 commands[] = { 0x0a, 0xda, 0xdb, 0xdc, 0x54, 0x0c };

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
	valid = !of_address_to_resource(np, 0, &res) &&
		res.start == 0x1c2c0000 && resource_size(&res) == 0x300;
	valid = valid && !of_address_to_resource(np, 1, &res) &&
		res.start == 0x1c2e0100 && resource_size(&res) == 0x700;
	of_node_put(np);
	if (!valid)
		return -ENODEV;
	pmu = ioremap(0x18062000, PAGE_SIZE);
	if (!pmu || !(readl(pmu + 0x204) & 1) || !(readl(pmu + 0x284) & 1))
		goto out;
	decon = ioremap(0x1c240000, PAGE_SIZE);
	dsi = ioremap(0x1c2c0000, PAGE_SIZE);
	if (!decon || !dsi)
		goto out;
	if ((readl(decon + 0x30) & 0x11) != 0x10)
		goto out;
	ret = readl_poll_timeout(decon + 0x20, state, state & BIT(5), 50, 100000);
	if (ret)
		goto out;
	pr_info("pixel-dsi: ver=%08x clk=%08x esc=%08x config=%08x fifo=%08x cmd=%08x sfr=%08x irq=%08x mask=%08x\n",
		readl(dsi), readl(dsi + 0x20), readl(dsi + 0x2c), readl(dsi + 0x4c),
		readl(dsi + 0x68), readl(dsi + 0x80), readl(dsi + 0x64),
		readl(dsi + 0x50), readl(dsi + 0x54));
	pr_info("pixel-dsi: host underrun=%08x te0=%08x te1=%08x trigger=%08x\n",
		readl(dsi + 0x34), readl(dsi + 0x84), readl(dsi + 0x88), readl(decon + 0x30));
	phy = ioremap(0x1c2e0100, 0x100);
	if (!phy) {
		ret = -ENOMEM;
		goto out;
	}
	pr_info("pixel-dsi: PLL %08x %08x %08x\n", readl(phy), readl(phy + 4), readl(phy + 8));
	iounmap(phy);
	ret = -ENODEV;
	if (readl(dsi) != 0x02060000 || (readl(dsi + 0x4c) & BIT(18)) ||
	    (readl(dsi + 0x80) & (BIT(16) | BIT(17))))
		goto out;
	for (unsigned int i = 0; i < ARRAY_SIZE(commands); i++) {
		ret = read_dcs(commands[i], 1);
		if (ret)
			break;
	}
	if (!ret && vendor) {
		ret = vendor_key(true);
		if (!ret)
			ret = read_dcs(0x60, 4);
		if (!ret)
			ret = read_dcs(0xb9, 16);
		if (!ret)
			ret = read_dcs(0xbd, 8);
		if (vendor_key(false) && !ret)
			ret = -EIO;
	}
	pr_info("pixel-dsi: finished ret=%d fifo=%08x irq=%08x\n",
		ret, readl(dsi + 0x68), readl(dsi + 0x50));
out:
	if (dsi)
		iounmap(dsi);
	if (decon)
		iounmap(decon);
	if (pmu)
		iounmap(pmu);
	return ret;
}
static void __exit dsi_probe_exit(void)
{
}
module_init(dsi_probe_init);
module_exit(dsi_probe_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Bounded Pixel retained DSIM DCS read probe");
