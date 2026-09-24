// SPDX-License-Identifier: GPL-2.0-only
/* Read-only copy of the bootloader's project records in shared memory, for
 * the sensor DSP's /proc/oppoVersion files (docs/sensors-20260924.md):
 * item 135, which the Oplus kernels read as their project data (OCDT: project,
 * PCB, RF), and item 136, OnePlus's own project_info. Each appears as
 * /sys/kernel/debug/guacamole_smem/itemN, copied at load; nothing is written
 * to shared memory. Unload to remove. */
#include <linux/debugfs.h>
#include <linux/err.h>
#include <linux/module.h>
#include <linux/slab.h>
#include <linux/soc/qcom/smem.h>

static const unsigned int items[] = { 135, 136 };
static struct debugfs_blob_wrapper blobs[ARRAY_SIZE(items)];
static struct dentry *dir;

static int __init smem_info_init(void)
{
    char name[16];
    size_t size;
    void *p;
    int i;

    if (!qcom_smem_is_available())
        return -EPROBE_DEFER;
    dir = debugfs_create_dir("guacamole_smem", NULL);
    for (i = 0; i < ARRAY_SIZE(items); i++) {
        p = qcom_smem_get(QCOM_SMEM_HOST_ANY, items[i], &size);
        if (IS_ERR(p)) {
            pr_info("guacamole_smem_info: item %u: %ld\n", items[i], PTR_ERR(p));
            continue;
        }
        blobs[i].data = kmemdup(p, size, GFP_KERNEL);
        if (!blobs[i].data)
            continue;
        blobs[i].size = size;
        snprintf(name, sizeof(name), "item%u", items[i]);
        debugfs_create_blob(name, 0400, dir, &blobs[i]);
    }
    return 0;
}

static void __exit smem_info_exit(void)
{
    int i;

    debugfs_remove_recursive(dir);
    for (i = 0; i < ARRAY_SIZE(items); i++)
        kfree(blobs[i].data);
}
module_init(smem_info_init);
module_exit(smem_info_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Guacamole: read-only copy of the SMEM project records (items 135, 136)");
