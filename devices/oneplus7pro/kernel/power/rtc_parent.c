// SPDX-License-Identifier: GPL-2.0-only
/* Live OF changes look up platform parents, but this PMIC is an SPMI device. */
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_platform.h>
#include <linux/platform_device.h>
#include <linux/spmi.h>

static int __init rtc_parent_init(void)
{
    struct device_node *node, *parent_node;
    struct platform_device *pdev;
    struct spmi_device *parent;
    int ret = 0;

    if (!of_machine_is_compatible("oneplus,guacamole"))
        return -ENODEV;
    node = of_find_node_by_path("/soc@0/spmi@c440000/pmic@0/rtc@6000");
    if (!node)
        return -ENODEV;
    parent_node = of_get_parent(node);
    parent = spmi_find_device_by_of_node(parent_node);
    of_node_put(parent_node);
    if (!parent) {
        ret = -ENODEV;
        goto out_node;
    }
    pdev = of_find_device_by_node(node);
    if (!pdev) {
        ret = -ENODEV;
        goto out_parent;
    }
    /* Only replace the unbound orphan produced by the generic OF notifier. */
    if (pdev->dev.driver || pdev->dev.parent == &parent->dev) {
        platform_device_put(pdev);
        ret = -EBUSY;
        goto out_parent;
    }
    of_platform_device_destroy(&pdev->dev, NULL);
    platform_device_put(pdev);
    pdev = of_platform_device_create(node, NULL, &parent->dev);
    if (!pdev)
        ret = -ENODEV;
    else
        pr_info("guacamole RTC device recreated under its SPMI parent\n");
out_parent:
    spmi_device_put(parent);
out_node:
    of_node_put(node);
    return ret;
}
module_init(rtc_parent_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Guacamole live RTC overlay parent repair; reboot to remove");
