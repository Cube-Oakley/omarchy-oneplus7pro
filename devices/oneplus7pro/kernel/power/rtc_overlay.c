// SPDX-License-Identifier: GPL-2.0-only
/* Temporary diagnostic; reboot to remove live DT consumers. */
#include <linux/init.h>
#include <linux/module.h>
#include <linux/of.h>
#include "rtc_dtbo.h"

static int overlay_id = -1;
static int __init rtc_overlay_init(void)
{
    struct device_node *node;
    bool available;
    int ret;

    if (!of_machine_is_compatible("oneplus,guacamole"))
        return -ENODEV;
    node = of_find_node_by_path("/soc@0/spmi@c440000");
    if (!node)
        return -ENODEV;
    available = of_device_is_available(node);
    of_node_put(node);
    if (!available)
        return -ENODEV;
    node = of_find_node_by_path("/soc@0/spmi@c440000/pmic@0/rtc@6000");
    if (!node)
        return -ENODEV;
    available = of_device_is_available(node);
    if (of_property_read_bool(node, "allow-set-time") ||
        of_property_read_bool(node, "qcom,uefi-rtc-info") ||
        of_find_property(node, "nvmem-cells", NULL)) {
        of_node_put(node);
        return -EINVAL;
    }
    of_node_put(node);
    if (available)
        return -EBUSY;
    ret = of_overlay_fdt_apply(rtc_dtbo, sizeof(rtc_dtbo), &overlay_id, NULL);
    if (ret) {
        if (overlay_id >= 0)
            of_overlay_remove(&overlay_id);
        return ret;
    }
    pr_info("guacamole RTC alarm overlay applied; reboot to remove\n");
    return 0;
}
module_init(rtc_overlay_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("OnePlus 7 Pro PM8150 RTC alarm diagnostic");
