// SPDX-License-Identifier: GPL-2.0-only
/* One-time software-state snapshot. No votes, MMIO, firmware messages or PM calls.
 * Private PAS layout is extracted from the exact native5 source at build time.
 */
#include <linux/debugfs.h>
#include <linux/firmware/qcom/qcom_scm.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/pm_runtime.h>
#include <linux/remoteproc.h>
#include <linux/seq_file.h>
#include <linux/utsname.h>
#include <generated/utsrelease.h>
#include "qcom_common.h"
#include "qcom_q6v5.h"
#include "pas-layout.h"

static struct dentry *entry;
static char snapshot[1024];

static int state_show(struct seq_file *s, void *unused)
{
    seq_puts(s, snapshot);
    return 0;
}
DEFINE_SHOW_ATTRIBUTE(state);

static int __init snapshot_init(void)
{
    struct device *dev;
    struct qcom_pas *pas;
    struct rproc *rproc;
    int ret = -ENODEV, len, i;

    if (strcmp(init_uts_ns.name.release, UTS_RELEASE) ||
        !of_machine_is_compatible("oneplus,guacamole"))
        return -ENODEV;
    dev = bus_find_device_by_name(&platform_bus_type, NULL, "4080000.remoteproc");
    if (!dev)
        return -ENODEV;
    device_lock(dev);
    if (!dev->driver || strcmp(dev->driver->name, "qcom_q6v5_pas"))
        goto unlock_device;
    pas = dev_get_drvdata(dev);
    if (!pas || pas->dev != dev || !pas->rproc ||
        pas->q6v5.dev != dev || pas->q6v5.rproc != pas->rproc)
        goto unlock_device;
    rproc = pas->rproc;
    if (!mutex_trylock(&rproc->lock)) {
        ret = -EBUSY;
        goto unlock_device;
    }
    if (rproc->priv != pas || rproc->state != RPROC_RUNNING ||
        pas->proxy_pd_count < 0 || pas->proxy_pd_count > ARRAY_SIZE(pas->proxy_pds))
        goto unlock_rproc;
    len = scnprintf(snapshot, sizeof(snapshot),
        "snapshot_only=1\nrproc_running=1\nq6v5_running=%u\n"
        "handover_issued=%u\nqmp_attached=%u\nload_state=%s\n"
        "interconnect_attached=%u\nproxy_domain_count=%d\n",
        READ_ONCE(pas->q6v5.running), READ_ONCE(pas->q6v5.handover_issued),
        !IS_ERR_OR_NULL(pas->q6v5.qmp), pas->q6v5.load_state ?: "(none)",
        !IS_ERR_OR_NULL(pas->q6v5.path), pas->proxy_pd_count);
    for (i = 0; i < pas->proxy_pd_count; i++) {
        struct device *pd = pas->proxy_pds[i];
        if (IS_ERR_OR_NULL(pd))
            continue;
        len += scnprintf(snapshot + len, sizeof(snapshot) - len,
            "proxy[%d]=%s runtime_status=%d usage_count=%d\n", i,
            dev_name(pd), READ_ONCE(pd->power.runtime_status),
            atomic_read(&pd->power.usage_count));
    }
    ret = 0;
unlock_rproc:
    mutex_unlock(&rproc->lock);
unlock_device:
    device_unlock(dev);
    put_device(dev);
    if (ret)
        return ret;
    entry = debugfs_create_file("guacamole_modem_handoff", 0400, NULL, NULL, &state_fops);
    if (IS_ERR(entry))
        return PTR_ERR(entry);
    return 0;
}

static void __exit snapshot_exit(void)
{
    debugfs_remove(entry);
}
module_init(snapshot_init);
module_exit(snapshot_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Native5 read-only modem handoff snapshot");
