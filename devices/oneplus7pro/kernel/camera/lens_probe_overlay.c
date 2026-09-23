// SPDX-License-Identifier: GPL-2.0-only
/* Adds the main camera's VAF rail and both candidate focus actuators, to
 * learn which one this unit has. Needs guacamole_camera applied and CCI
 * bound, so the I2C core creates the new clients. Reboot to remove. */
#include <linux/init.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_platform.h>
#include <linux/platform_device.h>
#include "lens_probe_dtbo.h"

static int overlay_id = -1;
static int __init lens_probe_init(void)
{
    struct platform_device *cci;
    struct device_node *node;
    bool bound;
    int ret;

    if (!of_machine_is_compatible("oneplus,guacamole"))
        return -ENODEV;
    node = of_find_node_by_path("/soc@0/cci@ac4a000");
    if (!node)
        return -ENODEV;
    cci = of_find_device_by_node(node);
    of_node_put(node);
    if (!cci)
        return -ENODEV;
    device_lock(&cci->dev);
    bound = cci->dev.driver != NULL;
    device_unlock(&cci->dev);
    put_device(&cci->dev);
    if (!bound)
        return -EPROBE_DEFER;
    ret = of_overlay_fdt_apply(lens_probe_dtbo, sizeof(lens_probe_dtbo), &overlay_id, NULL);
    if (ret && overlay_id >= 0)
        of_overlay_remove(&overlay_id);
    return ret;
}
module_init(lens_probe_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Guacamole main camera focus actuator identification; reboot to remove");
