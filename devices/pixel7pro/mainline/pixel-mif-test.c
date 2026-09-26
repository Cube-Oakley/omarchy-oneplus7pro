// SPDX-License-Identifier: GPL-2.0-only
/* Bounded CCF/ACPM memory-bandwidth experiment for the cheetah RAM desktop.
 * The stock live DT's mif_int_map explicitly pairs 1352 MHz MIF with 200 MHz
 * INT. Firmware performs the DVFS transition; no PLL/voltage/MMIO writes here.
 * Exclusive CCF rate ownership, seven thermal guards, timed baseline restore.
 */
#include <linux/clk.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/thermal.h>
#include <linux/workqueue.h>

static bool probe;
module_param(probe, bool, 0400);
static struct clk *mif, *interconnect;
static struct thermal_zone_device *zones[7];
static struct delayed_work stop_work;
static unsigned long deadline, saved_rate;
static bool active, exclusive;

static bool temperatures_ok(void)
{
	int temp;

	for (unsigned int i = 0; i < ARRAY_SIZE(zones); i++)
		if (thermal_zone_get_temp(zones[i], &temp) || temp < 5000 || temp >= 55000)
			return false;
	return true;
}

static void restore(void)
{
	int ret;

	if (!active)
		return;
	ret = clk_set_rate(mif, saved_rate);
	pr_info("pixel-mif: restored request=%lu actual=%lu ret=%d\n",
		saved_rate, clk_get_rate(mif), ret);
	active = false;
}

static void monitor(struct work_struct *work)
{
	if (!temperatures_ok() || time_after_eq(jiffies, deadline)) {
		restore();
		return;
	}
	schedule_delayed_work(&stop_work, HZ);
}

static int __init mif_init(void)
{
	static const char * const names[] = {
		"pixel-big", "pixel-mid", "pixel-little", "pixel-g3d",
		"pixel-isp", "pixel-tpu", "pixel-aur",
	};
	struct of_phandle_args args = { .args_count = 1 };
	struct device_node *np;
	const __be32 *map;
	int length, ret = -ENODEV;
	bool found = false;

	if (!probe || !of_machine_is_compatible("google,GS201 CHEETAH"))
		return -EINVAL;
	np = of_find_node_by_path("/exynos_devfreq/devfreq_mif@17000010");
	if (!np)
		return -ENODEV;
	map = of_get_property(np, "mif_int_map", &length);
	if (map && !(length % 8))
		for (unsigned int i = 0; i < length / 4; i += 2)
			if (be32_to_cpu(map[i]) == 1352000 && be32_to_cpu(map[i + 1]) == 200000)
				found = true;
	of_node_put(np);
	if (!found)
		return -ENODEV;
	for (unsigned int i = 0; i < ARRAY_SIZE(zones); i++) {
		zones[i] = thermal_zone_get_zone_by_name(names[i]);
		if (IS_ERR(zones[i]))
			return PTR_ERR(zones[i]);
	}
	if (!temperatures_ok())
		return -ERANGE;
	args.np = of_find_node_by_path("/power-management");
	if (!args.np)
		return -ENODEV;
	args.args[0] = 0;
	mif = of_clk_get_from_provider(&args);
	args.args[0] = 1;
	interconnect = of_clk_get_from_provider(&args);
	of_node_put(args.np);
	if (IS_ERR(mif) || IS_ERR(interconnect))
		goto put;
	saved_rate = clk_get_rate(mif);
	if (saved_rate != 421000000 || clk_get_rate(interconnect) != 200000000)
		goto put;
	ret = clk_rate_exclusive_get(mif);
	if (ret)
		goto put;
	exclusive = true;
	active = true;
	ret = clk_set_rate(mif, 1352000000);
	if (ret || clk_get_rate(mif) != 1352000000) {
		ret = ret ?: -EIO;
		restore();
		goto put;
	}
	pr_info("pixel-mif: firmware DVFS baseline=%lu test=%lu INT=%lu; 90 second limit\n",
		saved_rate, clk_get_rate(mif), clk_get_rate(interconnect));
	deadline = jiffies + 90 * HZ;
	INIT_DELAYED_WORK(&stop_work, monitor);
	schedule_delayed_work(&stop_work, HZ);
	return 0;
put:
	if (exclusive)
		clk_rate_exclusive_put(mif);
	if (!IS_ERR(mif))
		clk_put(mif);
	if (!IS_ERR(interconnect))
		clk_put(interconnect);
	return ret;
}

static void __exit mif_exit(void)
{
	cancel_delayed_work_sync(&stop_work);
	restore();
	clk_rate_exclusive_put(mif);
	clk_put(mif);
	clk_put(interconnect);
}
module_init(mif_init);
module_exit(mif_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Bounded cheetah CCF memory-bandwidth experiment");
