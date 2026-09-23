// SPDX-License-Identifier: GPL-2.0-only
/* Load only with the machine and q6asm-dai drivers unloaded. Reboot to remove. */
#include <linux/init.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_platform.h>
#include <linux/platform_device.h>
#include "microphone_dtbo.h"

static int overlay_id = -1;
static int __init microphone_init(void)
{
    struct device_node *node;
    struct platform_device *pdev;
    int ret;
    if (!of_machine_is_compatible("oneplus,guacamole"))
        return -ENODEV;
    node = of_find_node_by_path("/sound");
    if (!node)
        return -ENODEV;
    pdev = of_find_device_by_node(node);
    of_node_put(node);
    if (!pdev)
        return -ENODEV;
    device_lock(&pdev->dev);
    ret = pdev->dev.driver ? -EBUSY : 0;
    device_unlock(&pdev->dev);
    put_device(&pdev->dev);
    if (ret)
        return ret;
    ret = of_overlay_fdt_apply(microphone_dtbo, sizeof(microphone_dtbo),
                               &overlay_id, NULL);
    if (ret && overlay_id >= 0)
        of_overlay_remove(&overlay_id);
    return ret;
}
module_init(microphone_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Guacamole microphone routing trial; reboot to remove");
