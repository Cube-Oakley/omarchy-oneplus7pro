// SPDX-License-Identifier: GPL-2.0-only
/* Applies one embedded device tree overlay when loaded; reboot to remove.
 * The build generates overlay.h per overlay: the blob, a node the overlay
 * adds (so a second load refuses instead of applying it twice) and the module
 * description. See scripts/build_controls.sh. */
#include <linux/init.h>
#include <linux/module.h>
#include <linux/of.h>
#include "overlay.h"

static int overlay_id = -1;

static int __init overlay_init(void)
{
    struct device_node *node;
    int ret;

    if (!of_machine_is_compatible("oneplus,guacamole"))
        return -ENODEV;
    node = of_find_node_by_path(OVERLAY_NODE);
    if (node) {
        of_node_put(node);
        return -EEXIST;
    }
    ret = of_overlay_fdt_apply(overlay_dtbo, sizeof(overlay_dtbo), &overlay_id, NULL);
    if (ret && overlay_id >= 0)
        of_overlay_remove(&overlay_id);
    return ret;
}
module_init(overlay_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION(OVERLAY_DESCRIPTION);
