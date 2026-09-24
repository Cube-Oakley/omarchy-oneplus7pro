// SPDX-License-Identifier: GPL-2.0-only
/* Enables PM8150L's second slave id and its flash block (guacamole-flash.dts),
 * then registers the SPMI device for that slave id, as the SPMI core does for
 * each enabled PMIC when the bus starts: the slave id was disabled then, and
 * the bus does not watch for later changes. The PMIC driver then creates the
 * flash device for leds-qcom-flash. Reboot to remove. */
#include <linux/init.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/spmi.h>
#include "overlay.h"

#define PMIC_BASE "/soc@0/spmi@c440000/pmic@4"
#define PMIC_FLASH "/soc@0/spmi@c440000/pmic@5"
#define PMIC_FLASH_SID 5

static int overlay_id = -1;

static int __init flash_init(void)
{
    struct device_node *base, *node;
    struct spmi_device *sibling, *sdev;
    int ret;

    if (!of_machine_is_compatible("oneplus,guacamole"))
        return -ENODEV;

    node = of_find_node_by_path(PMIC_FLASH);
    if (!node)
        return -ENODEV;
    sdev = spmi_find_device_by_of_node(node);
    if (sdev) {
        put_device(&sdev->dev);
        of_node_put(node);
        return -EEXIST;
    }

    /* The first slave id's device leads to the controller. */
    base = of_find_node_by_path(PMIC_BASE);
    sibling = base ? spmi_find_device_by_of_node(base) : NULL;
    of_node_put(base);
    if (!sibling) {
        of_node_put(node);
        return -ENODEV;
    }

    ret = of_overlay_fdt_apply(overlay_dtbo, sizeof(overlay_dtbo), &overlay_id, NULL);
    if (ret) {
        if (overlay_id >= 0)
            of_overlay_remove(&overlay_id);
        goto out;
    }

    sdev = spmi_device_alloc(sibling->ctrl);
    if (!sdev) {
        ret = -ENOMEM;
        goto out;
    }
    device_set_node(&sdev->dev, of_fwnode_handle(node));
    sdev->usid = PMIC_FLASH_SID;
    ret = spmi_device_add(sdev);
    if (ret)
        spmi_device_put(sdev);
out:
    put_device(&sibling->dev);
    of_node_put(node);
    return ret;
}
module_init(flash_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Guacamole rear flash: PM8150L slave id 5 and its flash block; reboot to remove");
