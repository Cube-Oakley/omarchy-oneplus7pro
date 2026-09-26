// SPDX-License-Identifier: GPL-2.0-only
/* Adds CCI0 (and CCI1 for the ultra-wide), the camera subsystem, PM8009
 * LDO1/3/4 and camera slots: the IMX586 main camera (guacamole_camera), the
 * S5K3M5 telephoto (guacamole_camera_tele), the IMX481 ultra-wide
 * (guacamole_camera_wide) or all three (guacamole_camera_rear), built from
 * guacamole-camera.dts. One per boot.
 * Refuses unless the RPMh hold and camcc are both bound: camcc's arrival runs
 * rpmhpd's sync_state, which without the hold releases the modem's power
 * hold (docs/camera-20260922.md). Reboot to remove. */
#include <linux/init.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_platform.h>
#include <linux/platform_device.h>
#include "camera_dtbo.h"

static bool bound(const char *path)
{
    struct platform_device *pdev;
    struct device_node *node;
    bool result;

    node = of_find_node_by_path(path);
    if (!node)
        return false;
    pdev = of_find_device_by_node(node);
    of_node_put(node);
    if (!pdev)
        return false;
    device_lock(&pdev->dev);
    result = pdev->dev.driver != NULL;
    device_unlock(&pdev->dev);
    put_device(&pdev->dev);
    return result;
}

static int overlay_id = -1;
static int __init camera_init(void)
{
    struct device_node *node;
    int ret;

    if (!of_machine_is_compatible("oneplus,guacamole"))
        return -ENODEV;
    node = of_find_node_by_path("/soc@0/cci@ac4a000");
    if (node) {
        of_node_put(node);
        return -EEXIST;
    }
    if (!bound("/rpmhpd-hold") || !bound("/soc@0/clock-controller@ad00000"))
        return -EPERM;
    ret = of_overlay_fdt_apply(camera_dtbo, sizeof(camera_dtbo), &overlay_id, NULL);
    if (ret && overlay_id >= 0)
        of_overlay_remove(&overlay_id);
    return ret;
}
module_init(camera_init);
MODULE_LICENSE("GPL");
#ifndef CAMERA_SLOT
#define CAMERA_SLOT "IMX586"
#endif
MODULE_DESCRIPTION("Guacamole camera overlay (CCI0, CAMSS, " CAMERA_SLOT "); reboot to remove");
