// SPDX-License-Identifier: GPL-2.0
/* Exact-build native5 passive CCF reference snapshots. Pins consumer handles without
 * preparing clocks. CPU callbacks read cached scalar fields only: no provider
 * callbacks, clock mutations, MMIO, allocation, logging or sleeping locks.
 * Counts are individually sampled, not an atomic snapshot of the whole tree.
 */
#include <linux/clk.h>
#include <linux/clk-provider.h>
#include <linux/cpu_pm.h>
#include <linux/debugfs.h>
#include <linux/kref.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/percpu.h>
#include <linux/seq_file.h>
#include <linux/slab.h>
#include <linux/suspend.h>
#include <linux/utsname.h>
#include <clocksource/arm_arch_timer.h>
#include <asm/sysreg.h>
#include <generated/utsrelease.h>
#include <generated/utsversion.h>
#include "clock-layout.h"

#define LIMIT 512
struct provider_spec { const char *compatible; const unsigned int *ids; unsigned int count; };
#include "clock-providers.h"
struct watched {
    struct clk *clk;
    struct clk_core *core;
    char name[96];
    unsigned long flags;
};
static struct watched clocks[LIMIT];
static unsigned int count, missing;
struct row { unsigned int prepare, enable; struct clk_core *parent; };
struct capture { struct row rows[LIMIT]; bool valid; };
struct cpu_entry { struct capture clocks; u64 entered; bool pending; };
static struct cpu_entry __percpu *entries;
static struct capture longest_entry, longest_exit;
static u64 longest_ticks, entered_ticks, exited_ticks;
static unsigned int generation, longest_cpu;
static bool recording;
static DEFINE_RAW_SPINLOCK(history_lock);
static struct dentry *directory;

static void capture(struct capture *sample)
{
    unsigned int i;
    for (i = 0; i < count; i++) {
        struct clk_core *core = clocks[i].core;
        sample->rows[i].prepare = READ_ONCE(core->prepare_count);
        sample->rows[i].enable = READ_ONCE(core->enable_count);
        /* Pointer identity only. Never dereference an unpinned parent. */
        sample->rows[i].parent = READ_ONCE(core->parent);
    }
    sample->valid = true;
}

static int cpu_event(struct notifier_block *nb, unsigned long action, void *data)
{
    struct cpu_entry *entry;
    unsigned long flags;
    u64 now;

    if (!READ_ONCE(recording))
        return NOTIFY_OK;
    if (action != CPU_PM_ENTER && action != CPU_PM_ENTER_FAILED &&
        action != CPU_PM_EXIT)
        return NOTIFY_OK;
    /* Contention may lose a sample; never delay a CPU's sleep entry. */
    if (!raw_spin_trylock_irqsave(&history_lock, flags)) {
        this_cpu_ptr(entries)->pending = false;
        return NOTIFY_OK;
    }
    if (!recording)
        goto done;
    entry = this_cpu_ptr(entries);
    if (action == CPU_PM_ENTER) {
        capture(&entry->clocks);
        entry->entered = arch_timer_read_counter();
        entry->pending = true;
    } else if (action == CPU_PM_ENTER_FAILED) {
        entry->pending = false;
    } else if (action == CPU_PM_EXIT && entry->pending) {
        now = arch_timer_read_counter();
        if (now - entry->entered > longest_ticks) {
            longest_ticks = now - entry->entered;
            longest_cpu = raw_smp_processor_id();
            entered_ticks = entry->entered;
            exited_ticks = now;
            longest_entry = entry->clocks;
            capture(&longest_exit);
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
    unsigned int cpu;
    unsigned long flags;
    raw_spin_lock_irqsave(&history_lock, flags);
    if (action == PM_SUSPEND_PREPARE) {
        recording = false;
        longest_ticks = entered_ticks = exited_ticks = 0;
        longest_entry.valid = longest_exit.valid = false;
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

static int index_of(struct clk_core *core)
{
    unsigned int i;
    if (!core) return -1;
    for (i = 0; i < count; i++)
        if (clocks[i].core == core) return i;
    return -2; /* Parent not in captured inventory. */
}

static void print_capture(struct seq_file *s, const char *phase, struct capture *sample)
{
    unsigned int i;
    seq_printf(s, "%s valid=%u count=%u\n", phase, sample->valid, count);
    if (!sample->valid) return;
    for (i = 0; i < count; i++)
        seq_printf(s, "%s %u %s prepare=%u enable=%u parent=%d flags=%lx\n",
                   phase, i, clocks[i].name, sample->rows[i].prepare,
                   sample->rows[i].enable, index_of(sample->rows[i].parent),
                   clocks[i].flags);
}

static int history_show(struct seq_file *s, void *unused)
{
    struct capture *samples;
    u64 ticks, start, end;
    unsigned int gen, cpu;
    unsigned long flags;
    bool active;
    samples = kcalloc(2, sizeof(*samples), GFP_KERNEL);
    if (!samples) return -ENOMEM;
    raw_spin_lock_irqsave(&history_lock, flags);
    samples[0] = longest_entry; samples[1] = longest_exit;
    ticks = longest_ticks; start = entered_ticks; end = exited_ticks;
    gen = generation; cpu = longest_cpu; active = recording;
    raw_spin_unlock_irqrestore(&history_lock, flags);
    seq_printf(s, "generation=%u recording=%u cpu=%u ticks=%llu counter_hz=%llu enter=%llu exit=%llu missing_provider_clocks=%u\n",
               gen, active, cpu, ticks, (u64)read_sysreg(cntfrq_el0), start, end, missing);
    seq_puts(s, "Cached CCF references, not hardware clock states. Scalar reads are not a coherent tree snapshot.\n");
    print_capture(s, "entry", &samples[0]);
    print_capture(s, "exit", &samples[1]);
    kfree(samples);
    return 0;
}
DEFINE_SHOW_ATTRIBUTE(history);

static int current_show(struct seq_file *s, void *unused)
{
    struct capture *sample = kzalloc(sizeof(*sample), GFP_KERNEL);
    if (!sample) return -ENOMEM;
    capture(sample);
    seq_printf(s, "missing_provider_clocks=%u\n", missing);
    print_capture(s, "current", sample);
    kfree(sample);
    return 0;
}
DEFINE_SHOW_ATTRIBUTE(current);

/* Takes ownership of clk. Duplicate references are released immediately. */
static int add_clock(struct clk *clk)
{
    struct clk_hw *hw = __clk_get_hw(clk), *parent;
    struct clk_core *core;
    if (!hw || !hw->core) {
        pr_err("clock-refs: clock lacks a hardware/core handle\n");
        clk_put(clk); return -EINVAL;
    }
    core = hw->core;
    if (index_of(core) >= 0) { clk_put(clk); return 0; }
    if (count == LIMIT) { clk_put(clk); return -E2BIG; }
    if (core->hw != hw || !core->name) {
        pr_err("clock-refs: clock core identity check failed\n");
        clk_put(clk); return -EINVAL;
    }
    clocks[count].clk = clk; clocks[count].core = core;
    strscpy(clocks[count].name, core->name, sizeof(clocks[count].name));
    clocks[count++].flags = core->flags;
    parent = clk_hw_get_parent(hw);
    if (parent) {
        clk = clk_hw_get_clk(parent, "guacamole-clock-observer");
        if (IS_ERR(clk)) return PTR_ERR(clk);
        return add_clock(clk);
    }
    return 0;
}

static void put_clocks(void)
{
    while (count) clk_put(clocks[--count].clk);
}

static int __init observer_init(void)
{
    struct device_node *node;
    unsigned int p, i;
    int ret;
    if (strcmp(init_utsname()->release, UTS_RELEASE) ||
        strcmp(init_utsname()->version, UTS_VERSION) ||
        !of_machine_is_compatible("oneplus,guacamole")) {
        pr_err("clock-refs: requires %s %s on guacamole\n", UTS_RELEASE, UTS_VERSION);
        return -EINVAL;
    }
    for (p = 0; p < ARRAY_SIZE(providers); p++) {
        for_each_compatible_node(node, NULL, providers[p].compatible) {
            if (!of_device_is_available(node)) continue;
            for (i = 0; i < providers[p].count; i++) {
                struct of_phandle_args spec = { .np=node, .args_count=1,
                                               .args={ providers[p].ids[i] } };
                struct clk *clk = of_clk_get_from_provider(&spec);
                if (IS_ERR(clk)) {
                    if (PTR_ERR(clk) == -ENOMEM) { ret=-ENOMEM; goto put_node; }
                    missing++;
                    continue;
                }
                ret = add_clock(clk);
                if (ret) {
                    pr_err("clock-refs: provider %s id %u failed: %d\n",
                           providers[p].compatible, providers[p].ids[i], ret);
                    goto put_node;
                }
            }
        }
    }
    if (!count) { ret=-ENODEV; goto release; }
    entries = alloc_percpu(struct cpu_entry);
    if (!entries) { ret=-ENOMEM; goto release; }
    ret = register_pm_notifier(&system_observer);
    if (ret) goto free_entries;
    ret = cpu_pm_register_notifier(&cpu_observer);
    if (ret) goto unregister_pm;
    directory = debugfs_create_dir("guacamole_clock_refs", NULL);
    if (IS_ERR(directory)) { ret=PTR_ERR(directory); goto unregister_cpu; }
    debugfs_create_file("current", 0400, directory, NULL, &current_fops);
    debugfs_create_file("last_suspend", 0400, directory, NULL, &history_fops);
    return 0;
unregister_cpu:
    cpu_pm_unregister_notifier(&cpu_observer);
    synchronize_rcu();
unregister_pm:
    unregister_pm_notifier(&system_observer);
free_entries:
    free_percpu(entries);
release:
    put_clocks();
    return ret;
put_node:
    of_node_put(node);
    goto release;
}

static void __exit observer_exit(void)
{
    debugfs_remove_recursive(directory);
    unregister_pm_notifier(&system_observer);
    WRITE_ONCE(recording, false);
    cpu_pm_unregister_notifier(&cpu_observer);
    synchronize_rcu();
    free_percpu(entries);
    put_clocks();
}
module_init(observer_init);
module_exit(observer_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Guacamole exact-build native5 passive CCF sleep reference observer");
