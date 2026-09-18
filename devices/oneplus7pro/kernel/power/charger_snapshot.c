// SPDX-License-Identifier: GPL-2.0-only
/* Read-only SMB5 status/config snapshot. No charger driver or register writes. */
#include <linux/module.h>
#include <linux/of.h>
#include <linux/spmi.h>

static const u16 registers[] = {
    0x0102, 0x0103, 0x0104, 0x0105,
    0x1006, 0x1007, 0x100b, 0x100d, 0x100e, 0x1010,
    0x1042, 0x1043, 0x1051, 0x1060, 0x1061, 0x1070, 0x1072, 0x107d,
    0x1107, 0x110a, 0x110b, 0x1210,
    0x1306, 0x1307, 0x1308, 0x1310, 0x1340, 0x1342,
    0x1362, 0x1365, 0x1366, 0x1370, 0x1380,
    0x1544, 0x1606, 0x1607, 0x1610, 0x1651, 0x1653,
};

static int __init charger_snapshot_init(void)
{
    struct device_node *node;
    struct spmi_device *parent, *target;
    unsigned int i;
    int ret;
    u8 value;

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
        spmi_device_put(parent);
        return -ENOMEM;
    }
    /* Unregistered target: no probe, driver, IRQ or peripheral setup. */
    target->usid = 2;
    pr_info("guacamole charger snapshot begin (read-only, USID 2)\n");
    for (i = 0; i < ARRAY_SIZE(registers); i++) {
        ret = spmi_ext_register_readl(target, registers[i], &value, 1);
        if (ret) {
            pr_err("guacamole charger %04x read failed: %d\n", registers[i], ret);
            break;
        }
        pr_info("guacamole charger %04x=%02x\n", registers[i], value);
    }
    spmi_device_put(target);
    spmi_device_put(parent);
    return ret;
}
static void __exit charger_snapshot_exit(void) {}
module_init(charger_snapshot_init);
module_exit(charger_snapshot_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Read-only OnePlus 7 Pro SMB5 charger snapshot");
