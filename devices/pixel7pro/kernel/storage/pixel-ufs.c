// SPDX-License-Identifier: GPL-2.0-only
/* Experimental GS201 UFS host using the bootloader's powered PHY/clocks.
 * Standard Linux UFS/SCSI queues; no private block layer or MMIO data path.
 * No runtime suspend, crypto, clock scaling or HS gear changes yet.
 */
#include <linux/dma-mapping.h>
#include <linux/io.h>
#include <linux/module.h>
#include <linux/of_address.h>
#include <linux/of_irq.h>
#include <linux/of_platform.h>
#include <linux/platform_device.h>
#include <linux/pm_runtime.h>
#include <scsi/scsi_host.h>
#include <ufs/ufshcd.h>
#include <ufs/ufshci.h>
#include <ufs/unipro.h>

static struct platform_device *pixel_pdev;
static bool reprobe;
module_param(reprobe, bool, 0400);

static u64 pixel_dma_mask = DMA_BIT_MASK(64);

struct pixel_ufs {
	void __iomem *vendor;
};

static int pixel_init(struct ufs_hba *hba)
{
	struct pixel_ufs *p;

	p = devm_kzalloc(hba->dev, sizeof(*p), GFP_KERNEL);
	if (!p)
		return -ENOMEM;
	p->vendor = devm_platform_ioremap_resource(to_platform_device(hba->dev), 1);
	if (IS_ERR(p->vendor))
		return PTR_ERR(p->vendor);
	ufshcd_set_variant(hba, p);
	/* GS201 stock DT has fixed-prdt-req_list-ocs: do not copy the older
	 * Exynos PRDT-byte-granularity or inverted request-clear quirks.
	 */
	hba->quirks = UFSHCD_QUIRK_SKIP_DEF_UNIPRO_TIMEOUT_SETTING |
		      UFSHCD_QUIRK_BROKEN_AUTO_HIBERN8;
	hba->caps = 0;
	hba->rpm_lvl = UFS_PM_LVL_0;
	hba->spm_lvl = UFS_PM_LVL_0;
	hba->lanes_per_direction = 2;
	hba->host->max_segment_size = 4096;
	if (ufshcd_readl(hba, REG_UFS_VERSION) != 0x300 ||
	    (!reprobe && ufshcd_readl(hba, REG_CONTROLLER_ENABLE) != 1) ||
	    !(ufshcd_readl(hba, REG_CONTROLLER_STATUS) & DEVICE_PRESENT) ||
	    ufshcd_readl(hba, REG_UTP_TRANSFER_REQ_DOOR_BELL) ||
	    ufshcd_readl(hba, REG_UTP_TASK_REQ_DOOR_BELL) ||
	    readl(p->vendor + 0x60) != 0xa || readl(p->vendor + 0xb0))
		return dev_err_probe(hba->dev, -EINVAL, "unexpected UFS handoff state\n");
	return 0;
}

static int pixel_link(struct ufs_hba *hba, enum ufs_notify_change_status status)
{
	struct pixel_ufs *p = ufshcd_get_variant(hba);

	if (status == PRE_CHANGE) {
		/* GS201 vendor ufs-cal-if.c initializes these standard UniPro
		 * attributes before link startup, just as mainline GS101 does.
		 */
		static const u32 attrs[][2] = {
			{ N_DEVICEID, 0 }, { N_DEVICEID_VALID, 1 },
			{ T_PEERDEVICEID, 1 }, { T_CONNECTIONSTATE, 1 },
		};
		u32 state;
		int i, ret;

		ret = ufshcd_dme_get(hba, UIC_ARG_MIB(T_CONNECTIONSTATE), &state);
		if (ret)
			return ret;
		dev_info(hba->dev, "inherited CPort connection=%u\n", state);
		for (i = 0; i < ARRAY_SIZE(attrs); i++) {
			ret = ufshcd_dme_set(hba, UIC_ARG_MIB(attrs[i][0]), attrs[i][1]);
			if (ret)
				return ret;
		}
	}

	if (status == POST_CHANGE) {
		/* Standard unencrypted PRDT, 4 KiB maximum segment. */
		writel(0xc, p->vendor);
		writel(0xc, p->vendor + 4);
		writel(0xa, p->vendor + 0x60);
	}
	return 0;
}

static int pixel_negotiate(struct ufs_hba *hba,
			   const struct ufs_pa_layer_attr *desired,
			   struct ufs_pa_layer_attr *final)
{
	/* Stay in the link-startup PWM gear until PHY calibration is owned. */
	*final = hba->pwr_info;
	return 0;
}

static void pixel_xfer(struct ufs_hba *hba, int tag, bool scsi)
{
	struct pixel_ufs *p = ufshcd_get_variant(hba);
	u32 value = readl(p->vendor + 0x40);

	writel(scsi ? value | BIT(tag) : value & ~BIT(tag), p->vendor + 0x40);
}

static int pixel_dma(struct ufs_hba *hba)
{
	int ret;

	/* Keep descriptor allocations below 4 GiB in this retained handoff.
	 * Data buffers need the advertised 64-bit addressing: RAM extends
	 * above 4 GiB and the kernel has no 32-bit bounce pool.
	 */
	if (!(hba->capabilities & MASK_64_ADDRESSING_SUPPORT))
		return -EINVAL;
	ret = dma_set_mask(hba->dev, DMA_BIT_MASK(64));
	if (ret)
		return ret;
	return dma_set_coherent_mask(hba->dev, DMA_BIT_MASK(32));
}

static const struct ufs_hba_variant_ops pixel_ops = {
	.name = "gs201-handoff",
	.init = pixel_init,
	.set_dma_mask = pixel_dma,
	.link_startup_notify = pixel_link,
	.negotiate_pwr_mode = pixel_negotiate,
	.setup_xfer_req = pixel_xfer,
};

static int pixel_probe(struct platform_device *pdev)
{
	struct ufs_hba *hba;
	void __iomem *base;
	int ret, irq;

	base = devm_platform_ioremap_resource(pdev, 0);
	if (IS_ERR(base))
		return PTR_ERR(base);
	irq = platform_get_irq(pdev, 0);
	if (irq < 0)
		return irq;
	ret = ufshcd_alloc_host(&pdev->dev, &hba);
	if (ret)
		return ret;
	hba->vops = &pixel_ops;
	ret = ufshcd_init(hba, base, irq);
	if (ret)
		return dev_err_probe(&pdev->dev, ret, "UFS startup failed\n");
	pm_runtime_set_active(&pdev->dev);
	pm_runtime_enable(&pdev->dev);
	pm_runtime_forbid(&pdev->dev);
	return 0;
}

static void pixel_remove(struct platform_device *pdev)
{
	struct ufs_hba *hba = platform_get_drvdata(pdev);

	ufshcd_remove(hba);
	pm_runtime_disable(&pdev->dev);
}

static struct platform_driver pixel_driver = {
	.probe = pixel_probe,
	.remove = pixel_remove,
	.driver = { .name = "pixel-ufs", .probe_type = PROBE_FORCE_SYNCHRONOUS },
};

static int __init pixel_ufs_init(void)
{
	struct device_node *np;
	struct platform_device *stock;
	struct resource res[3];
	int ret, irq, attempt;

	if (!of_machine_is_compatible("google,GS201 CHEETAH"))
		return -ENODEV;
	np = of_find_node_by_path("/ufs@0x14700000");
	if (!np)
		return -ENODEV;
	stock = of_find_device_by_node(np);
	if (stock && stock->dev.driver) {
		put_device(&stock->dev);
		of_node_put(np);
		return -EBUSY;
	}
	if (stock)
		put_device(&stock->dev);
	ret = of_address_to_resource(np, 0, &res[0]);
	if (!ret)
		ret = of_address_to_resource(np, 1, &res[1]);
	irq = irq_of_parse_and_map(np, 0);
	of_node_put(np);
	if (ret || !irq || res[0].start != 0x14700000 ||
	    res[1].start != 0x14701100)
		return -EINVAL;
	res[2] = (struct resource)DEFINE_RES_IRQ(irq);
	ret = platform_driver_register(&pixel_driver);
	if (ret)
		return ret;
	attempt = 0;
retry:
	pixel_pdev = platform_device_alloc("pixel-ufs", PLATFORM_DEVID_NONE);
	if (!pixel_pdev) {
		ret = -ENOMEM;
		goto unregister;
	}
	pixel_pdev->dev.dma_mask = &pixel_dma_mask;
	pixel_pdev->dev.coherent_dma_mask = pixel_dma_mask;
	/* Stock SYSREG_HSI2 IOCC readback is 0x13 (read/write coherent). */
	dev_set_dma_coherent(&pixel_pdev->dev);
	ret = platform_device_add_resources(pixel_pdev, res, ARRAY_SIZE(res));
	if (!ret)
		ret = platform_device_add(pixel_pdev);
	if (!ret) {
		if (pixel_pdev->dev.driver)
			return 0;
		/* The first inherited link can answer QUERY with invalid 0xff.
		 * A complete failed-probe teardown and one fresh initialization
		 * recovers it. No block devices exist at this point. Never retry
		 * a bound controller or bypass the remaining handoff checks.
		 */
		platform_device_unregister(pixel_pdev);
		pixel_pdev = NULL;
		if (!attempt++) {
			reprobe = true;
			pr_info("pixel-ufs: retrying once after failed handoff initialization\n");
			goto retry;
		}
		ret = -ENODEV;
		goto unregister;
	}
	platform_device_put(pixel_pdev);
unregister:
	platform_driver_unregister(&pixel_driver);
	return ret;
}

static void __exit pixel_ufs_exit(void)
{
	platform_device_unregister(pixel_pdev);
	platform_driver_unregister(&pixel_driver);
}
module_init(pixel_ufs_init);
module_exit(pixel_ufs_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("GS201 UFS bring-up on retained PHY and clocks");
