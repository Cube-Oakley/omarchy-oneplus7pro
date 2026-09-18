// SPDX-License-Identifier: GPL-2.0-only
#include <linux/init.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_platform.h>
#include <linux/platform_device.h>
#include "audio_card_dtbo.h"
#ifndef PUBLISH_ONLY
static int overlay_id = -1;
#endif
static int publish_sound(void)
{
    struct device_node *node = of_find_node_by_path("/sound");
    struct platform_device *pdev;
    if (!node || !of_device_is_compatible(node, "qcom,sm8150-sndcard")) {
        of_node_put(node);
        return -ENODEV;
    }
    pdev = of_find_device_by_node(node);
    if (pdev) {
        put_device(&pdev->dev);
        of_node_put(node);
        return 0;
    }
    /* The base DT has an empty /sound node, already considered available.
     * Adding compatible/status cannot trigger the disabled->enabled notifier. */
    pdev = of_platform_device_create(node, NULL, NULL);
    of_node_put(node);
    return pdev ? 0 : -ENODEV;
}
static int __init audio_card_overlay_init(void)
{
#ifndef PUBLISH_ONLY
    struct device_node *node;
    bool available;
    int ret;
    if (!of_machine_is_compatible("oneplus,guacamole"))
        return -ENODEV;
    node = of_find_node_by_path("/soc@0/remoteproc@17300000");
    available = node && of_device_is_available(node);
    of_node_put(node);
    if (!available)
        return -ENODEV;
    node = of_find_node_by_path("/soc@0/slim-ngd@171c0000");
    if (!node)
        return -ENODEV;
    available = of_device_is_available(node);
    of_node_put(node);
    if (available)
        return -EBUSY;
    ret = of_overlay_fdt_apply(audio_card_dtbo, sizeof(audio_card_dtbo), &overlay_id, NULL);
    if (ret && overlay_id >= 0)
        of_overlay_remove(&overlay_id);
    if (!ret)
        pr_info("guacamole internal audio-card overlay applied; reboot to remove\n");
    return ret ? ret : publish_sound();
#else
    if (!of_machine_is_compatible("oneplus,guacamole"))
        return -ENODEV;
    return publish_sound();
#endif
}
module_init(audio_card_overlay_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Guacamole WCD9340 codec and initial ALSA card test");
