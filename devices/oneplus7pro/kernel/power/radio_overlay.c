// SPDX-License-Identifier: GPL-2.0-only
/* Single-apply diagnostic; reboot to remove live DT consumers. */
#include <linux/init.h>
#include <linux/module.h>
#include <linux/of.h>
#include "radio_dtbo.h"

static int overlay_id = -1;
static int __init radio_overlay_init(void)
{
    struct device_node *node;
    bool available;
    int ret;

    if (!of_machine_is_compatible("oneplus,guacamole"))
        return -ENODEV;
    node = of_find_node_by_path("/reserved-memory/rmtfs-lower-guard@f2900000");
    if (!node)
        return -EINVAL;
    of_node_put(node);
    node = of_find_node_by_path("/reserved-memory/rmtfs-upper-guard@f2b01000");
    if (!node)
        return -EINVAL;
    of_node_put(node);
    node = of_find_node_by_path(TEST_NODE);
    if (!node)
        return -ENODEV;
    available = of_device_is_available(node);
    of_node_put(node);
    if (available)
        return -EBUSY;
    ret = of_overlay_fdt_apply(radio_dtbo, sizeof(radio_dtbo), &overlay_id, NULL);
    if (ret) {
        pr_err("guacamole radio overlay failed: %d\n", ret);
        if (overlay_id >= 0)
            of_overlay_remove(&overlay_id);
        return ret;
    }
    pr_info("guacamole radio overlay applied to %s; reboot to remove\n", TEST_NODE);
    return 0;
}
module_init(radio_overlay_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Staged guacamole radio bring-up DT overlay");
