// SPDX-License-Identifier: GPL-2.0-only
/* One-minute, 500 mA / 4.20 V diagnostic. Not an unattended charger driver. */
#include <linux/delay.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/power_supply.h>
#include <linux/spmi.h>
#include <linux/workqueue.h>

static struct spmi_device *parent, *target;
static struct power_supply *battery;
static struct delayed_work monitor;
static unsigned long deadline;
static u8 saved_cmd, saved_float;
static bool changed;

static int read_reg(u16 addr, u8 *value)
{
    return spmi_ext_register_readl(target, addr, value, 1);
}

static int write_verify(u16 addr, u8 value)
{
    u8 actual;
    int ret = spmi_ext_register_writel(target, addr, &value, 1);
    if (ret)
        return ret;
    ret = read_reg(addr, &actual);
    return ret ? ret : (actual == value ? 0 : -EIO);
}

static int sample(void)
{
    union power_supply_propval temp, voltage, amperage;
    u8 path, thermal, fault, fcc, fv;
    int ret;

    ret = power_supply_get_property(battery, POWER_SUPPLY_PROP_TEMP, &temp);
    if (ret)
        return ret;
    ret = power_supply_get_property(battery, POWER_SUPPLY_PROP_VOLTAGE_NOW, &voltage);
    if (ret)
        return ret;
    ret = power_supply_get_property(battery, POWER_SUPPLY_PROP_CURRENT_NOW, &amperage);
    if (ret)
        return ret;
    if (read_reg(0x110b, &path) || read_reg(0x100d, &thermal) ||
        read_reg(0x1007, &fault) || read_reg(0x1061, &fcc) || read_reg(0x1070, &fv))
        return -EIO;
    pr_info("charger-trial: temp=%d dC voltage=%d uV current=%d uA path=%02x thermal=%02x fault=%02x\n",
            temp.intval, voltage.intval, amperage.intval, path, thermal, fault);
    if (temp.intval < 100 || temp.intval >= 400 || voltage.intval < 3500000 ||
        voltage.intval >= 4220000 || amperage.intval > 650000 ||
        (path & 0x11) != 0x11 || (path & 0x40) || thermal || (fault & 2) ||
        fcc != 10 || (changed && fv != 60))
        return -ERANGE;
    return 0;
}

static void restore(void)
{
    int i, ret = 0;
    if (!changed)
        return;
    /* Confirm charging is off before restoring the former higher ceiling. */
    for (i = 0; i < 3; i++) {
        ret = write_verify(0x1042, saved_cmd);
        if (!ret)
            break;
        msleep(10);
    }
    if (ret) {
        pr_err("charger-trial: restore enable failed %d; retaining lower voltage ceiling\n", ret);
        return;
    }
    ret = write_verify(0x1070, saved_float);
    if (ret) {
        pr_err("charger-trial: charging disabled; float restore failed %d\n", ret);
        return;
    }
    changed = false;
    pr_info("charger-trial: stopped; original charge-enable and float voltage restored\n");
}

static void monitor_work(struct work_struct *work)
{
    int ret = sample();
    if (ret || time_after_eq(jiffies, deadline)) {
        pr_info("charger-trial: ending (sample=%d timeout=%d)\n", ret,
                time_after_eq(jiffies, deadline));
        restore();
        return;
    }
    schedule_delayed_work(&monitor, msecs_to_jiffies(2000));
}

static void release_refs(void)
{
    if (battery)
        power_supply_put(battery);
    if (target)
        spmi_device_put(target);
    if (parent)
        spmi_device_put(parent);
}

static int __init charger_trial_init(void)
{
    struct device_node *node;
    u8 subtype;
    int ret = -ENODEV;

    if (!of_machine_is_compatible("oneplus,guacamole"))
        return -ENODEV;
    node = of_find_node_by_path("/soc@0/spmi@c440000/pmic@0");
    if (!node)
        return -ENODEV;
    parent = spmi_find_device_by_of_node(node);
    of_node_put(node);
    if (!parent)
        return -ENODEV;
    target = spmi_device_alloc(parent->ctrl);
    if (!target) {
        ret = -ENOMEM;
        goto fail;
    }
    target->usid = 2;
    battery = power_supply_get_by_name("bq27541-0");
    if (!battery)
        goto fail;
    if (read_reg(0x0105, &subtype) || subtype != 0x20 ||
        read_reg(0x1042, &saved_cmd) || saved_cmd != 0 ||
        read_reg(0x1070, &saved_float) || saved_float != 0x4d) {
        ret = -EINVAL;
        goto fail;
    }
    ret = sample();
    if (ret)
        goto fail;
    /* PM8150b: float = 3.60 V + 10 mV/step; FCC already 10 * 50 mA.
     * Leave USB-C, input limits, thermal protection and gauge config intact.
     */
    changed = true;
    ret = write_verify(0x1070, 60);
    if (ret)
        goto fail;
    ret = write_verify(0x1042, 1);
    if (ret)
        goto fail;
    deadline = jiffies + msecs_to_jiffies(60000);
    INIT_DELAYED_WORK(&monitor, monitor_work);
    schedule_delayed_work(&monitor, msecs_to_jiffies(2000));
    pr_info("charger-trial: enabled for at most 60 seconds, 500 mA / 4.20 V\n");
    return 0;
fail:
    if (changed)
        restore();
    release_refs();
    return ret;
}

static void __exit charger_trial_exit(void)
{
    cancel_delayed_work_sync(&monitor);
    restore();
    release_refs();
}
module_init(charger_trial_init);
module_exit(charger_trial_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Bounded OnePlus 7 Pro charger diagnostic, no autoload");
