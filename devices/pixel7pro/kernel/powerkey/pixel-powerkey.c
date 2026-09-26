// SPDX-License-Identifier: GPL-2.0-only
/* S2MPG12 power key through firmware's read-only PMIC status protocol.
 * GS201 stock DT: ACPM IPC channel 2, PMIC bus 0, PM bank 1.
 * Google gs b3c9095e: S2MPG12_PM_STATUS1=0x0a, PWRON=BIT(0).
 * This initial input path polls; it cannot wake a suspended CPU.
 */
#include <linux/err.h>
#include <linux/firmware/samsung/exynos-acpm-protocol.h>
#include <linux/input.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/workqueue.h>

static struct device *keydev;
static struct input_dev *input;
static struct acpm_handle *acpm;
static struct delayed_work poll_work;
static unsigned int errors;
static bool pressed, candidate;

static int read_pressed(bool *value)
{
	u8 status;
	int ret = acpm->ops->pmic.read_reg(acpm, 2, 1, 0x0a, 0, &status);

	if (!ret)
		*value = !!(status & BIT(0));
	return ret;
}

static void poll_key(struct work_struct *work)
{
	bool value;
	int ret = read_pressed(&value);

	if (ret) {
		if (++errors >= 5) {
			/* Release on transport failure, then stop instead of flooding ACPM. */
			input_report_key(input, KEY_POWER, 0);
			input_sync(input);
			pr_err("pixel-powerkey: PMIC read failed %d; polling stopped\n", ret);
			return;
		}
	} else {
		errors = 0;
		if (value == candidate && value != pressed) {
			pressed = value;
			input_report_key(input, KEY_POWER, pressed);
			input_sync(input);
			pr_info("pixel-powerkey: %s\n", pressed ? "pressed" : "released");
		}
		candidate = value;
	}
	schedule_delayed_work(&poll_work, msecs_to_jiffies(20));
}

static int __init pixel_powerkey_init(void)
{
	struct device_node *np;
	int ret;

	np = of_find_compatible_node(NULL, NULL, "samsung,s2mpg12mfd");
	if (!np)
		return -ENODEV;
	of_node_put(np);
	keydev = root_device_register("pixel-powerkey");
	if (IS_ERR(keydev))
		return PTR_ERR(keydev);
	np = of_find_node_by_path("/power-management");
	if (!np) {
		ret = -ENODEV;
		goto unregister;
	}
	acpm = devm_acpm_get_by_node(keydev, np);
	of_node_put(np);
	if (IS_ERR(acpm)) {
		ret = PTR_ERR(acpm);
		goto unregister;
	}
	ret = read_pressed(&pressed);
	if (ret)
		goto unregister;
	candidate = pressed;
	input = input_allocate_device();
	if (!input) {
		ret = -ENOMEM;
		goto unregister;
	}
	input->name = "Pixel S2MPG12 power key";
	input->phys = "pixel-powerkey/input0";
	input->id.bustype = BUS_HOST;
	input->dev.parent = keydev;
	input_set_capability(input, EV_KEY, KEY_POWER);
	ret = input_register_device(input);
	if (ret) {
		input_free_device(input);
		goto unregister;
	}
	input_report_key(input, KEY_POWER, pressed);
	input_sync(input);
	INIT_DELAYED_WORK(&poll_work, poll_key);
	schedule_delayed_work(&poll_work, msecs_to_jiffies(20));
	pr_info("pixel-powerkey: read-only STATUS1 polling active, initial=%u\n", pressed);
	return 0;
unregister:
	root_device_unregister(keydev);
	return ret;
}

static void __exit pixel_powerkey_exit(void)
{
	cancel_delayed_work_sync(&poll_work);
	input_unregister_device(input);
	root_device_unregister(keydev);
}

module_init(pixel_powerkey_init);
module_exit(pixel_powerkey_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Pixel GS201 S2MPG12 power key status input");
