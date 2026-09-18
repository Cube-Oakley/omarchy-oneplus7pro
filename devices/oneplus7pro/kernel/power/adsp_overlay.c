// SPDX-License-Identifier: GPL-2.0-only
/* One-shot audio DSP test; deliberately no unload or automatic boot hook. */
#include <linux/init.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_address.h>
#include "adsp_dtbo.h"

static int overlay_id = -1;
static int __init adsp_overlay_init(void)
{
    struct device_node *node, *memory;
    struct resource resource;
    int ret;

    if (!of_machine_is_compatible("oneplus,guacamole"))
        return -ENODEV;
    node = of_find_node_by_path("/soc@0/remoteproc@17300000");
    if (!node)
        return -ENODEV;
    if (of_device_is_available(node)) {
        of_node_put(node);
        return -EBUSY;
    }
    memory = of_parse_phandle(node, "memory-region", 0);
    of_node_put(node);
    if (!memory)
        return -EINVAL;
    ret = of_address_to_resource(memory, 0, &resource);
    if (!ret && (!of_property_read_bool(memory, "no-map") ||
                resource.start != 0x8be00000 || resource_size(&resource) != 0x1e00000))
        ret = -EINVAL;
    of_node_put(memory);
    if (ret)
        return ret;
    ret = of_overlay_fdt_apply(adsp_dtbo, sizeof(adsp_dtbo), &overlay_id, NULL);
    if (ret) {
        if (overlay_id >= 0)
            of_overlay_remove(&overlay_id);
        return ret;
    }
    pr_info("guacamole ADSP-only overlay applied; reboot to remove\n");
    return 0;
}
module_init(adsp_overlay_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Guacamole isolated audio DSP bring-up");
