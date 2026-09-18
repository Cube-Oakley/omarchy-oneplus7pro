// SPDX-License-Identifier: GPL-2.0-only
#include <linux/init.h>
#include <linux/module.h>
#include <linux/of.h>
#include "amplifiers_dtbo.h"
static int overlay_id = -1;
static int __init amplifiers_init(void)
{
    struct device_node *node;
    bool available;
    int ret;
    if (!of_machine_is_compatible("oneplus,guacamole"))
        return -ENODEV;
    node = of_find_node_by_path("/soc@0/geniqup@8c0000/i2c@890000");
    if (!node)
        return -ENODEV;
    available = of_device_is_available(node);
    of_node_put(node);
    if (available)
        return -EBUSY;
    ret = of_overlay_fdt_apply(amplifiers_dtbo, sizeof(amplifiers_dtbo), &overlay_id, NULL);
    if (ret && overlay_id >= 0)
        of_overlay_remove(&overlay_id);
    if (!ret)
        pr_info("guacamole amplifier bus enabled; reset GPIOs untouched\n");
    return ret;
}
module_init(amplifiers_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Guacamole isolated amplifier bus overlay");
