// SPDX-License-Identifier: GPL-2.0
/* Native5-only diagnostic: copy the existing RPMh software vote cache under
 * its own lock. No MMIO writes, RPMh requests or firmware changes. Optional
 * CPU/system PM observers record votes but never veto or request a transition.
 * Private cache layouts are extracted from the exact kernel source at build.
 */
#include <linux/debugfs.h>
#include <linux/cpu_pm.h>
#include <linux/module.h>
#include <linux/percpu.h>
#include <linux/platform_device.h>
#include <linux/seq_file.h>
#include <linux/slab.h>
#include <linux/suspend.h>
#include <linux/utsname.h>
#include <clocksource/arm_arch_timer.h>
#include <asm/sysreg.h>
#include <generated/utsrelease.h>
#include "rpmh-internal.h"
#include "cache-layout.h"

#define LIMIT 256
struct vote { u32 addr, sleep, wake, state; };
static struct device *rsc_dev;
static struct rsc_drv *rsc;
static struct dentry *directory;

/* Only the longest CPU-PM interval within one system suspend is retained.
 * CNTVCT continues across s2idle, unlike the frozen Linux local clock.
 * Preallocated storage: no allocation, formatting or sleeping in callbacks.
 */
struct capture {
    struct vote rows[LIMIT];
    unsigned int count;
    bool valid, dirty, truncated;
};
struct cpu_entry {
    struct capture votes;
    u64 entered;
    bool pending;
};
static struct cpu_entry __percpu *entries;
static DEFINE_RAW_SPINLOCK(history_lock);
static struct capture longest_entry, longest_exit;
static u64 longest_ticks, entry_ticks, exit_ticks;
static unsigned int longest_cpu, generation;
static bool recording;

static void capture_votes(struct capture *out)
{
    struct cache_req *req;
    unsigned long flags;

    out->valid = false;
    out->count = 0;
    out->truncated = false;
    /* A busy cache must not delay/veto CPU entry. Mark a missing sample. */
    if (!spin_trylock_irqsave(&rsc->client.cache_lock, flags))
        return;
    out->dirty = rsc->client.dirty;
    list_for_each_entry(req, &rsc->client.cache, list) {
        if (out->count == LIMIT) { out->truncated = true; break; }
        out->rows[out->count++] = (struct vote) {
            req->addr, req->sleep_val, req->wake_val, 3
        };
    }
    out->valid = true;
    spin_unlock_irqrestore(&rsc->client.cache_lock, flags);
}

static int cpu_event(struct notifier_block *nb, unsigned long action, void *data)
{
    struct cpu_entry *entry;
    unsigned long flags;
    u64 now;

    if (!READ_ONCE(recording))
        return NOTIFY_OK;
    raw_spin_lock_irqsave(&history_lock, flags);
    if (!recording)
        goto done;
    entry = this_cpu_ptr(entries);
    if (action == CPU_PM_ENTER) {
        capture_votes(&entry->votes);
        entry->entered = arch_timer_read_counter();
        entry->pending = true;
    } else if (action == CPU_PM_ENTER_FAILED) {
        entry->pending = false;
    } else if (action == CPU_PM_EXIT && entry->pending) {
        now = arch_timer_read_counter();
        if (now - entry->entered > longest_ticks) {
            longest_ticks = now - entry->entered;
            longest_cpu = raw_smp_processor_id();
            entry_ticks = entry->entered;
            exit_ticks = now;
            longest_entry = entry->votes;
            capture_votes(&longest_exit);
        }
        entry->pending = false;
    }
done:
    raw_spin_unlock_irqrestore(&history_lock, flags);
    return NOTIFY_OK;
}
static struct notifier_block cpu_observer = { .notifier_call = cpu_event };

static int system_event(struct notifier_block *nb, unsigned long action, void *data)
{
    unsigned long flags;
    unsigned int cpu;

    raw_spin_lock_irqsave(&history_lock, flags);
    if (action == PM_SUSPEND_PREPARE) {
        recording = false;
        longest_ticks = entry_ticks = exit_ticks = 0;
        longest_entry.valid = longest_exit.valid = false;
        longest_entry.count = longest_exit.count = 0;
        for_each_possible_cpu(cpu)
            per_cpu_ptr(entries, cpu)->pending = false;
        generation++;
        recording = true;
    } else if (action == PM_POST_SUSPEND) {
        recording = false;
    }
    raw_spin_unlock_irqrestore(&history_lock, flags);
    return NOTIFY_OK;
}
static struct notifier_block system_observer = { .notifier_call = system_event };

static int interval_show(struct seq_file *s, void *unused)
{
    struct capture *copies;
    unsigned long flags;
    u64 ticks, start, end;
    unsigned int gen, cpu, i, phase;
    bool active;

    copies = kcalloc(2, sizeof(*copies), GFP_KERNEL);
    if (!copies)
        return -ENOMEM;
    raw_spin_lock_irqsave(&history_lock, flags);
    copies[0] = longest_entry;
    copies[1] = longest_exit;
    gen = generation; cpu = longest_cpu; ticks = longest_ticks;
    start = entry_ticks; end = exit_ticks; active = recording;
    raw_spin_unlock_irqrestore(&history_lock, flags);
    seq_printf(s, "generation=%u recording=%u cpu=%u ticks=%llu counter_hz=%llu enter=%llu exit=%llu\n",
               gen, active, cpu, ticks, (u64)read_sysreg(cntfrq_el0), start, end);
    seq_puts(s, "Software cache at CPU-PM entry/exit, not a hardware vote trace. Batch votes excluded.\n");
    for (phase = 0; phase < 2; phase++) {
        seq_printf(s, "%s valid=%u dirty=%u truncated=%u count=%u\n",
                   phase ? "exit" : "entry", copies[phase].valid,
                   copies[phase].dirty, copies[phase].truncated, copies[phase].count);
        for (i = 0; i < copies[phase].count; i++)
            seq_printf(s, "%s %08x %08x %08x\n", phase ? "exit" : "entry",
                       copies[phase].rows[i].addr, copies[phase].rows[i].sleep,
                       copies[phase].rows[i].wake);
    }
    kfree(copies);
    return 0;
}
DEFINE_SHOW_ATTRIBUTE(interval);

static int votes_show(struct seq_file *s, void *unused)
{
    struct vote *rows;
    struct cache_req *req;
    struct batch_cache_req *batch;
    unsigned long flags;
    unsigned int n = 0, i, j;
    bool dirty, truncated = false;

    rows = kcalloc(LIMIT, sizeof(*rows), GFP_KERNEL);
    if (!rows)
        return -ENOMEM;
    spin_lock_irqsave(&rsc->client.cache_lock, flags);
    dirty = rsc->client.dirty;
    list_for_each_entry(req, &rsc->client.cache, list) {
        if (n == LIMIT) { truncated = true; break; }
        rows[n++] = (struct vote) { req->addr, req->sleep_val, req->wake_val, 3 };
    }
    list_for_each_entry(batch, &rsc->client.batch_cache, list) {
        for (i = 0; i < batch->count; i++) {
            const struct tcs_request *msg = &batch->rpm_msgs[i].msg;
            for (j = 0; j < msg->num_cmds; j++) {
                if (n == LIMIT) { truncated = true; goto copied; }
                rows[n++] = (struct vote) { msg->cmds[j].addr,
                                           msg->cmds[j].data, 0, msg->state };
            }
        }
    }
copied:
    spin_unlock_irqrestore(&rsc->client.cache_lock, flags);
    seq_printf(s, "device=%s dirty=%u truncated=%u\n", dev_name(rsc_dev), dirty, truncated);
    seq_puts(s, "cache: address sleep wake (ffffffff = no cached vote)\n");
    for (i = 0; i < n; i++) {
        if (rows[i].state == 3)
            seq_printf(s, "cache %08x %08x %08x\n", rows[i].addr, rows[i].sleep, rows[i].wake);
        else
            seq_printf(s, "batch %08x state=%u value=%08x\n", rows[i].addr, rows[i].state, rows[i].sleep);
    }
    kfree(rows);
    return 0;
}
DEFINE_SHOW_ATTRIBUTE(votes);

static int __init votes_init(void)
{
    int ret;
    if (strcmp(init_utsname()->release, UTS_RELEASE))
        return -EINVAL;
    rsc_dev = bus_find_device_by_name(&platform_bus_type, NULL, "18200000.rsc");
    if (!rsc_dev)
        return -ENODEV;
    if (!rsc_dev->driver || strcmp(rsc_dev->driver->name, "rpmh"))
        goto bad_device;
    rsc = dev_get_drvdata(rsc_dev);
    if (!rsc || rsc->dev != rsc_dev)
        goto bad_device;
    entries = alloc_percpu(struct cpu_entry);
    if (!entries) { ret = -ENOMEM; goto put_rsc; }
    ret = register_pm_notifier(&system_observer);
    if (ret)
        goto free_entries;
    ret = cpu_pm_register_notifier(&cpu_observer);
    if (ret)
        goto unregister_system;
    directory = debugfs_create_dir("guacamole_rpmh_votes", NULL);
    if (IS_ERR(directory)) {
        ret = PTR_ERR(directory);
        goto unregister_cpu;
    }
    debugfs_create_file("cache", 0400, directory, NULL, &votes_fops);
    debugfs_create_file("last_suspend", 0400, directory, NULL, &interval_fops);
    return 0;
unregister_cpu:
    cpu_pm_unregister_notifier(&cpu_observer);
    synchronize_rcu();
unregister_system:
    unregister_pm_notifier(&system_observer);
free_entries:
    free_percpu(entries);
put_rsc:
    put_device(rsc_dev);
    return ret;
bad_device:
    put_device(rsc_dev);
    return -ENODEV;
}

static void __exit votes_exit(void)
{
    debugfs_remove_recursive(directory);
    unregister_pm_notifier(&system_observer);
    WRITE_ONCE(recording, false);
    cpu_pm_unregister_notifier(&cpu_observer);
    synchronize_rcu();
    free_percpu(entries);
    put_device(rsc_dev);
}
module_init(votes_init);
module_exit(votes_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Native5 read-only RPMh software vote cache diagnostic");
