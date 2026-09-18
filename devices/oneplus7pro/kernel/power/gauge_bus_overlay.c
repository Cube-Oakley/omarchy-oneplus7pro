// SPDX-License-Identifier: GPL-2.0-only
/* Temporary bus diagnostic. Keep loaded until reboot. */
#include <linux/init.h>
#include <linux/module.h>
#include <linux/of.h>
#include "gauge_bus_dtbo.h"

static int overlay_id = -1;
static int __init gauge_bus_overlay_init(void)
{
    struct device_node *bus;
    bool available;
    int ret;

    if (!of_machine_is_compatible("oneplus,guacamole"))
        return -ENODEV;
    bus = of_find_node_by_path("/soc@0/geniqup@ac0000/i2c@a80000");
    if (!bus)
        return -ENODEV;
    available = of_device_is_available(bus);
    of_node_put(bus);
    if (available)
        return -EBUSY;
    ret = of_overlay_fdt_apply(gauge_bus_dtbo, sizeof(gauge_bus_dtbo),
                               &overlay_id, NULL);
    if (ret) {
        pr_err("guacamole gauge-bus overlay failed: %d (id %d)\n", ret, overlay_id);
        if (overlay_id >= 0)
            of_overlay_remove(&overlay_id);
        return ret;
    }
    pr_info("guacamole gauge-bus overlay applied: %d; reboot to remove\n", overlay_id);
    return 0;
}
module_init(gauge_bus_overlay_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Temporary OnePlus 7 Pro external battery gauge bus");
