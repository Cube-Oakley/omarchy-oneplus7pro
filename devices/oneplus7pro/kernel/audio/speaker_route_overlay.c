// SPDX-License-Identifier: GPL-2.0-only
#include <linux/init.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_platform.h>
#include <linux/platform_device.h>
#include "speaker_route_dtbo.h"
static int overlay_id = -1;
static int __init speaker_route_init(void)
{
    struct device_node *node;
    struct platform_device *pdev;
    int ret;
    if (!of_machine_is_compatible("oneplus,guacamole"))
        return -ENODEV;
    /* Card must be unbound while its topology changes. */
    node = of_find_node_by_path("/sound");
    if (!node)
        return -ENODEV;
    pdev = of_find_device_by_node(node);
    of_node_put(node);
    if (!pdev)
        return -ENODEV;
    ret = pdev->dev.driver ? -EBUSY : 0;
    put_device(&pdev->dev);
    if (ret)
        return ret;
    ret = of_overlay_fdt_apply(speaker_route_dtbo, sizeof(speaker_route_dtbo), &overlay_id, NULL);
    if (ret && overlay_id >= 0)
        of_overlay_remove(&overlay_id);
    return ret;
}
module_init(speaker_route_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Guacamole QUAT MI2S speaker routing test");
