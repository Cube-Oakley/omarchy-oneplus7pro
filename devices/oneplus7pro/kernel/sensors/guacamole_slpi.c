// SPDX-License-Identifier: GPL-2.0-only
/* Starts the sensor DSP (guacamole-slpi.dts). Refuses unless SLPI's memory
 * region is the OEM one (0x98100000, 20 MiB) and the FastRPC pool exists,
 * as on kernel #193: on older boot DTBs SLPI's region overlaps the modem's,
 * and loading it there would overwrite running firmware. Reboot to stop;
 * SLPI cannot be restarted. See docs/sensors-20260924.md. */
#include <linux/init.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_address.h>
#include "overlay.h"

#define SLPI "/soc@0/remoteproc@2400000"
#define POOL "/reserved-memory/fastrpc-shared-pool"
#define SLPI_BASE 0x98100000
#define SLPI_SIZE 0x1400000

static int overlay_id = -1;

static int __init slpi_init(void)
{
    struct device_node *slpi, *region, *pool;
    struct resource res;
    bool available;
    int ret;

    if (!of_machine_is_compatible("oneplus,guacamole"))
        return -ENODEV;
    slpi = of_find_node_by_path(SLPI);
    if (!slpi)
        return -ENODEV;
    available = of_device_is_available(slpi);
    region = of_parse_phandle(slpi, "memory-region", 0);
    of_node_put(slpi);
    if (available) {
        of_node_put(region);
        return -EEXIST;
    }
    ret = region ? of_address_to_resource(region, 0, &res) : -ENODEV;
    of_node_put(region);
    if (ret)
        return ret;
    if (res.start != SLPI_BASE || resource_size(&res) != SLPI_SIZE) {
        pr_err("guacamole_slpi: SLPI region %pR is not the OEM one; boot kernel #193 or later\n", &res);
        return -EINVAL;
    }
    pool = of_find_node_by_path(POOL);
    if (!pool) {
        pr_err("guacamole_slpi: no FastRPC pool; boot kernel #193 or later\n");
        return -EINVAL;
    }
    of_node_put(pool);

    ret = of_overlay_fdt_apply(overlay_dtbo, sizeof(overlay_dtbo), &overlay_id, NULL);
    if (ret && overlay_id >= 0)
        of_overlay_remove(&overlay_id);
    return ret;
}
module_init(slpi_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Guacamole sensor DSP (SLPI) start; reboot to stop");
