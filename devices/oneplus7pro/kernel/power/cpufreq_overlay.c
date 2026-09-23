// SPDX-License-Identifier: GPL-2.0-only
/* Enables the CPU frequency hardware (see guacamole-cpufreq.dts). Reboot to remove. */
#include <linux/init.h>
#include <linux/module.h>
#include <linux/of.h>
#include "cpufreq_dtbo.h"

static int overlay_id = -1;
static int __init cpufreq_overlay_init(void)
{
    struct device_node *node;
    bool available;
    int ret;

    if (!of_machine_is_compatible("oneplus,guacamole"))
        return -ENODEV;
    node = of_find_node_by_path("/soc@0/cpufreq@18323000");
    if (!node)
        return -ENODEV;
    available = of_device_is_available(node);
    of_node_put(node);
    if (available)
        return -EEXIST;
    ret = of_overlay_fdt_apply(cpufreq_dtbo, sizeof(cpufreq_dtbo), &overlay_id, NULL);
    if (ret && overlay_id >= 0)
        of_overlay_remove(&overlay_id);
    return ret;
}
module_init(cpufreq_overlay_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Guacamole CPU frequency hardware overlay; reboot to remove");
