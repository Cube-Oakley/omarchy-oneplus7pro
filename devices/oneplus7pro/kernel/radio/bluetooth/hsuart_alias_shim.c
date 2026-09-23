// SPDX-License-Identifier: GPL-2.0-only
/*
 * Bring-up shim: registers the DT alias hsuart0 = UART13 at runtime.
 * qcom_geni_serial numbers a port without an alias from the highest "serial"
 * alias plus one; our boot DTB has no serial aliases, so that is -ENODEV + 1
 * and the probe fails with "Invalid line -19". Overlays cannot add aliases
 * (the list is built once by of_alias_scan()) and the list is not exported,
 * so userspace passes the addresses of aliases_lookup and of_mutex from
 * /proc/kallsyms and this module checks both with sprint_symbol() first.
 * Replace with "hsuart0 = &uart13;" in the next boot DTB. Cannot be unloaded.
 */
#include <linux/init.h>
#include <linux/kallsyms.h>
#include <linux/list.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/of.h>
#include <linux/slab.h>
#include <linux/string.h>

/* Must match drivers/of/of_private.h of the running kernel. */
struct alias_prop {
    struct list_head link;
    const char *alias;
    struct device_node *np;
    int id;
    char stem[];
};

static unsigned long aliases_lookup_addr, of_mutex_addr;
module_param(aliases_lookup_addr, ulong, 0400);
module_param(of_mutex_addr, ulong, 0400);

static bool is_symbol(unsigned long addr, const char *name)
{
    char found[KSYM_SYMBOL_LEN], want[KSYM_NAME_LEN + 8];

    if (!addr)
        return false;
    sprint_symbol(found, addr);
    snprintf(want, sizeof(want), "%s+0x0/", name);
    return !strncmp(found, want, strlen(want));
}

static int __init hsuart_alias_init(void)
{
    struct alias_prop *ap;
    struct device_node *np;
    struct mutex *lock;

    if (!of_machine_is_compatible("oneplus,guacamole"))
        return -ENODEV;
    if (!is_symbol(aliases_lookup_addr, "aliases_lookup") ||
        !is_symbol(of_mutex_addr, "of_mutex"))
        return -EINVAL;
    if (of_alias_get_highest_id("hsuart") >= 0)
        return -EEXIST;
    np = of_find_node_by_path("/soc@0/geniqup@cc0000/serial@c8c000");
    if (!np)
        return -ENODEV;
    ap = kzalloc(sizeof(*ap) + sizeof("hsuart"), GFP_KERNEL);
    if (!ap) {
        of_node_put(np);
        return -ENOMEM;
    }
    ap->alias = "hsuart0";
    ap->np = np; /* keeps the node reference for the alias's lifetime */
    ap->id = 0;
    strscpy(ap->stem, "hsuart", sizeof("hsuart"));
    lock = (struct mutex *)of_mutex_addr;
    mutex_lock(lock);
    list_add_tail(&ap->link, (struct list_head *)aliases_lookup_addr);
    mutex_unlock(lock);
    pr_info("guacamole: added DT alias hsuart0 -> %pOF\n", np);
    return 0;
}
module_init(hsuart_alias_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Guacamole hsuart0 alias for UART13 until the boot DTB has one");
