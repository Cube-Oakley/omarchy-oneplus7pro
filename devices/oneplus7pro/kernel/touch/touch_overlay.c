// SPDX-License-Identifier: GPL-2.0-only
/* Bring-up overlay loader. Intentionally stays loaded until reboot so that
 * no live consumers outlast the overlay. No changes to persistent firmware.
 */
#include <linux/init.h>
#include <linux/module.h>
#include <linux/of.h>
#include "touch_dtbo.h"

static int overlay_id = -1;
static int __init touch_overlay_init(void)
{
    int ret;
    if (!of_machine_is_compatible("oneplus,guacamole"))
        return -ENODEV;
    ret = of_overlay_fdt_apply(touch_dtbo, sizeof(touch_dtbo), &overlay_id, NULL);
    if (ret) {
        pr_err("guacamole touch overlay failed: %d (id %d)\n", ret, overlay_id);
        if (overlay_id >= 0)
            of_overlay_remove(&overlay_id);
        return ret;
    }
    pr_info("guacamole touch overlay applied: %d; reboot to remove\n", overlay_id);
    return 0;
}
module_init(touch_overlay_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Temporary OnePlus 7 Pro touchscreen DT overlay");
