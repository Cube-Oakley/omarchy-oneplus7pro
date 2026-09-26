// SPDX-License-Identifier: GPL-2.0-only
/* GS201 reboot target through the stock DT and Tensor secure PMU interface. */
#include <linux/arm-smccc.h>
#include <linux/io.h>
#include <linux/module.h>
#include <linux/of_address.h>
#include <linux/reboot.h>

static bool bootloader;
module_param(bootloader, bool, 0600);
MODULE_PARM_DESC(bootloader, "Select bootloader on the next orderly restart");
static void __iomem *pmu;
static phys_addr_t command_address;

static int pixel_restart_target(struct notifier_block *nb, unsigned long event,
				void *command)
{
	struct arm_smccc_res result;
	u32 value = bootloader ? 0xfc : 0;

	if (event != SYS_RESTART)
		return NOTIFY_DONE;
	/* Same interface as upstream tensor_sec_reg_write(). The stock GS201
	 * reboot driver writes mode 0xfc for bootloader and 0 for normal boot.
	 */
	arm_smccc_smc(0x82000504, command_address, 1, value, 0, 0, 0, 0, &result);
	if (result.a0 || readl(pmu + 0x810) != value)
		pr_err("pixel-reboot: target write failed: SMC=%ld readback=%#x\n",
		       (long)result.a0, readl(pmu + 0x810));
	else
		pr_info("pixel-reboot: next target=%s\n", bootloader ? "bootloader" : "normal");
	return NOTIFY_DONE;
}

static struct notifier_block pixel_reboot_nb = {
	.notifier_call = pixel_restart_target,
	.priority = INT_MAX,
};

static int __init pixel_reboot_init(void)
{
	struct device_node *np, *syscon;
	struct resource resource;
	u32 offset;
	int ret;

	if (!of_machine_is_compatible("google,GS201 CHEETAH"))
		return -ENODEV;
	np = of_find_node_by_path("/exynos-reboot");
	if (!np)
		return -ENODEV;
	if (!of_device_is_compatible(np, "samsung,exynos-reboot")) {
		of_node_put(np);
		return -EINVAL;
	}
	ret = of_property_read_u32(np, "reboot-cmd-offset", &offset);
	syscon = of_parse_phandle(np, "syscon", 0);
	of_node_put(np);
	if (ret || !syscon) {
		of_node_put(syscon);
		return -EINVAL;
	}
	ret = of_address_to_resource(syscon, 0, &resource);
	of_node_put(syscon);
	if (ret || offset != 0x810 || resource.start != 0x18060000 ||
	    resource_size(&resource) != 0x10000)
		return -EINVAL;
	command_address = resource.start + offset;
	pmu = ioremap(resource.start, 0x1000);
	if (!pmu)
		return -ENOMEM;
	ret = register_reboot_notifier(&pixel_reboot_nb);
	if (ret)
		iounmap(pmu);
	return ret;
}

static void __exit pixel_reboot_exit(void)
{
	unregister_reboot_notifier(&pixel_reboot_nb);
	iounmap(pmu);
}
module_init(pixel_reboot_init);
module_exit(pixel_reboot_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("GS201 normal/bootloader target for orderly native reboot");
