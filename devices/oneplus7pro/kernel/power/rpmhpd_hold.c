// SPDX-License-Identifier: GPL-2.0-only
/*
 * Holds the voted SM8150 RPMh power domains on at their top level, so rpmhpd's
 * sync_state (run when CAMCC binds) cannot release the corners the boot
 * clamp keeps today. The requested level is above every RPMh level, which
 * rpmhpd maps to each domain's top corner, as the clamp does.
 * Load before camcc-sm8150. Cannot be unloaded; reboot to remove.
 */
#include <linux/init.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/pm_domain.h>
#include <linux/pm_runtime.h>
#include "rpmhpd_hold_dtbo.h"

/* Above RPMH_REGULATOR_LEVEL_SUPER_TURBO_NO_CPR (480), the highest level. */
#define TOP_LEVEL U16_MAX

static const char *const domains[] = { "mss", "mx", "cx", "mmcx" };

static int hold_probe(struct platform_device *pdev)
{
    struct device *pd;
    int i, ret;

    for (i = 0; i < ARRAY_SIZE(domains); i++) {
        pd = dev_pm_domain_attach_by_name(&pdev->dev, domains[i]);
        if (IS_ERR_OR_NULL(pd))
            return dev_err_probe(&pdev->dev, pd ? PTR_ERR(pd) : -ENODEV,
                                 "attach %s\n", domains[i]);
        ret = pm_runtime_resume_and_get(pd);
        if (!ret)
            ret = dev_pm_genpd_set_performance_state(pd, TOP_LEVEL);
        if (ret)
            return dev_err_probe(&pdev->dev, ret, "hold %s\n", domains[i]);
    }
    /* The attached domains are never detached: the holds last until reboot. */
    dev_info(&pdev->dev, "holding %zu RPMh power domains at the top level\n", ARRAY_SIZE(domains));
    return 0;
}

static const struct of_device_id hold_match[] = {
    { .compatible = "oneplus,guacamole-rpmhpd-hold" },
    { }
};

static struct platform_driver hold_driver = {
    .probe = hold_probe,
    .driver = { .name = "guacamole-rpmhpd-hold", .of_match_table = hold_match,
                .suppress_bind_attrs = true },
};

static int overlay_id = -1;
static int __init hold_init(void)
{
    int ret;

    if (!of_machine_is_compatible("oneplus,guacamole"))
        return -ENODEV;
    ret = platform_driver_register(&hold_driver);
    if (ret)
        return ret;
    ret = of_overlay_fdt_apply(rpmhpd_hold_dtbo, sizeof(rpmhpd_hold_dtbo), &overlay_id, NULL);
    if (ret) {
        if (overlay_id >= 0)
            of_overlay_remove(&overlay_id);
        platform_driver_unregister(&hold_driver);
    }
    return ret;
}
module_init(hold_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Guacamole: hold RPMh power domains at the top level; reboot to remove");
