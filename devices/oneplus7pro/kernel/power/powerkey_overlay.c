// SPDX-License-Identifier: GPL-2.0-only
/* Temporary diagnostic; reboot to remove, never unload live DT consumers. */
#include <linux/init.h>
#include <linux/module.h>
#include <linux/of.h>
#include "powerkey_dtbo.h"

static int overlay_id = -1;
static int __init powerkey_overlay_init(void)
{
    struct device_node *bus;
    bool available;
    int ret;

    if (!of_machine_is_compatible("oneplus,guacamole"))
        return -ENODEV;
    bus = of_find_node_by_path("/soc@0/spmi@c440000");
    if (!bus)
        return -ENODEV;
    available = of_device_is_available(bus);
    of_node_put(bus);
    if (available)
        return -EBUSY;

    ret = of_overlay_fdt_apply(powerkey_dtbo, sizeof(powerkey_dtbo),
                               &overlay_id, NULL);
    if (ret) {
        pr_err("guacamole power-key overlay failed: %d (id %d)\n",
               ret, overlay_id);
        if (overlay_id >= 0)
            of_overlay_remove(&overlay_id);
        return ret;
    }
    pr_info("guacamole power-key overlay applied: %d; reboot to remove\n",
            overlay_id);
    return 0;
}
module_init(powerkey_overlay_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Temporary OnePlus 7 Pro PM8150 power-key DT overlay");
