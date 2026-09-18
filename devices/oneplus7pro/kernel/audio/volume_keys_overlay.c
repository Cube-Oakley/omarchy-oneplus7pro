// SPDX-License-Identifier: GPL-2.0-only
#include <linux/init.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_platform.h>
#include <linux/platform_device.h>
#include <linux/regmap.h>
#include <linux/spmi.h>
#include "volume_keys_dtbo.h"
static int overlay_id = -1;
static int __init volume_keys_init(void)
{
    struct device_node *node;
    struct spmi_device *pmic;
    struct platform_device *gpio;
    int ret;
    if (!of_machine_is_compatible("oneplus,guacamole"))
        return -ENODEV;
    node = of_find_node_by_path("/mobile-volume-keys");
    if (node) {
        of_node_put(node);
        return -EBUSY;
    }
    node = of_find_node_by_path("/soc@0/spmi@c440000/pmic@0/gpio@c000");
    if (!node)
        return -ENODEV;
    if (of_device_is_available(node)) {
        of_node_put(node);
        return -EBUSY;
    }
    pmic = spmi_find_device_by_of_node(node->parent);
    if (!pmic || !dev_get_regmap(&pmic->dev, NULL)) {
        if (pmic)
            spmi_device_put(pmic);
        of_node_put(node);
        return -EPROBE_DEFER;
    }
    /* OF's live notifier searches only the platform bus for the parent.
     * This PMIC is on SPMI; suppress its incorrect parentless creation and
     * explicitly publish the GPIO controller below the real PMIC instead. */
    if (of_node_test_and_set_flag(node, OF_POPULATED)) {
        spmi_device_put(pmic);
        of_node_put(node);
        return -EBUSY;
    }
    ret = of_overlay_fdt_apply(volume_keys_dtbo, sizeof(volume_keys_dtbo), &overlay_id, NULL);
    of_node_clear_flag(node, OF_POPULATED);
    if (ret && overlay_id >= 0)
        of_overlay_remove(&overlay_id);
    if (!ret) {
        gpio = of_platform_device_create(node, NULL, &pmic->dev);
        if (!gpio)
            ret = -ENODEV;
    }
    spmi_device_put(pmic);
    of_node_put(node);
    return ret;
}
module_init(volume_keys_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Guacamole PM8150 volume buttons");
