// SPDX-License-Identifier: GPL-2.0-only
/* Diagnostic overlay stays loaded until reboot to preserve live consumers. */
#include <linux/init.h>
#include <linux/module.h>
#include <linux/of.h>
#include "panel_graph_dtbo.h"

static int overlay_id = -1;
static int __init panel_graph_init(void)
{
    int ret;

    if (!of_machine_is_compatible("oneplus,guacamole"))
        return -ENODEV;
    ret = of_overlay_fdt_apply(panel_graph_dtbo, sizeof(panel_graph_dtbo),
                               &overlay_id, NULL);
    if (ret) {
        if (overlay_id >= 0)
            of_overlay_remove(&overlay_id);
        return ret;
    }
    pr_info("guacamole panel graph overlay applied: %d; reboot to remove\n",
            overlay_id);
    return 0;
}
module_init(panel_graph_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Temporary guacamole native1 display graph repair");
