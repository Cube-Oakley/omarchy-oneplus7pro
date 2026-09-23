// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Sr-0w

#include <linux/delay.h>
#include <linux/i2c.h>
#include <linux/module.h>
#include <linux/pm_runtime.h>
#include <linux/property.h>
#include <linux/regulator/consumer.h>

#include <media/v4l2-ctrls.h>
#include <media/v4l2-device.h>

#define LC898217XC_REG_STATUS		0xb3
#define LC898217XC_REG_POSITION		0x84
#define LC898217XC_STATUS_READY		0x00
#define LC898217XC_MAX_FOCUS_POS	1023
#define LC898217XC_DEFAULT_FOCUS_POS	50
#define LC898217XC_CTRL_STEPS		16
#define LC898217XC_CTRL_DELAY_US		1000
#define LC898217XC_POWER_DELAY_US	1000
#define LC898217XC_READY_RETRIES		20
#define LC898217XC_READY_DELAY_US	20000

static const char * const lc898217xc_supply_names[] = {
	"vdd",
	"vio",
};

struct lc898217xc_device {
	struct v4l2_ctrl_handler ctrls;
	struct v4l2_subdev sd;
	struct v4l2_ctrl *focus;
	struct regulator_bulk_data supplies[ARRAY_SIZE(lc898217xc_supply_names)];
	u16 focus_pos_max;
	u16 focus_pos_default;
};

static inline struct lc898217xc_device *
to_lc898217xc(struct v4l2_subdev *sd)
{
	return container_of(sd, struct lc898217xc_device, sd);
}

static int lc898217xc_read8(struct lc898217xc_device *vcm, u8 reg, u8 *val)
{
	struct i2c_client *client = v4l2_get_subdevdata(&vcm->sd);
	int ret;

	ret = i2c_smbus_read_byte_data(client, reg);
	if (ret < 0)
		return ret;

	*val = ret;
	return 0;
}

static int lc898217xc_set_position(struct lc898217xc_device *vcm, u16 position)
{
	struct i2c_client *client = v4l2_get_subdevdata(&vcm->sd);
	u8 buf[] = {
		LC898217XC_REG_POSITION,
		position >> 8,
		position & 0xff,
	};
	int ret;

	ret = i2c_master_send(client, buf, sizeof(buf));
	if (ret < 0)
		return ret;

	return ret == sizeof(buf) ? 0 : -EIO;
}

static int lc898217xc_wait_ready(struct lc898217xc_device *vcm)
{
	int ret;
	int i;
	u8 status = 0xff;

	for (i = 0; i < LC898217XC_READY_RETRIES; i++) {
		ret = lc898217xc_read8(vcm, LC898217XC_REG_STATUS, &status);
		if (!ret && status == LC898217XC_STATUS_READY)
			return 0;
		if (ret && ret != -ENXIO && ret != -EREMOTEIO)
			return ret;
		usleep_range(LC898217XC_READY_DELAY_US,
			     LC898217XC_READY_DELAY_US + 1000);
	}

	dev_err(vcm->sd.dev, "status 0x%02x did not become ready\n", status);
	return ret ? ret : -EBUSY;
}

static int lc898217xc_power_up(struct lc898217xc_device *vcm)
{
	int ret;

	ret = regulator_bulk_enable(ARRAY_SIZE(lc898217xc_supply_names),
				    vcm->supplies);
	if (ret)
		return ret;

	usleep_range(LC898217XC_POWER_DELAY_US,
		     LC898217XC_POWER_DELAY_US + 500);

	ret = lc898217xc_wait_ready(vcm);
	if (ret)
		goto err_disable;

	ret = lc898217xc_set_position(vcm, vcm->focus->val);
	if (ret)
		goto err_disable;

	return 0;

err_disable:
	regulator_bulk_disable(ARRAY_SIZE(lc898217xc_supply_names),
			       vcm->supplies);
	return ret;
}

static int lc898217xc_power_down(struct lc898217xc_device *vcm)
{
	int ret;
	int val;

	for (val = vcm->focus->val & ~(LC898217XC_CTRL_STEPS - 1);
	     val >= 0; val -= LC898217XC_CTRL_STEPS) {
		ret = lc898217xc_set_position(vcm, val);
		if (ret) {
			dev_warn_once(vcm->sd.dev,
				      "failed to park lens: %d\n", ret);
			break;
		}
		usleep_range(LC898217XC_CTRL_DELAY_US,
			     LC898217XC_CTRL_DELAY_US + 100);
	}

	return regulator_bulk_disable(ARRAY_SIZE(lc898217xc_supply_names),
				      vcm->supplies);
}

static int lc898217xc_set_ctrl(struct v4l2_ctrl *ctrl)
{
	struct lc898217xc_device *vcm = container_of(ctrl->handler,
						    struct lc898217xc_device,
						    ctrls);
	int ret;

	if (ctrl->id != V4L2_CID_FOCUS_ABSOLUTE)
		return -EINVAL;

	if (!pm_runtime_get_if_in_use(vcm->sd.dev))
		return 0;

	ret = lc898217xc_set_position(vcm, ctrl->val);
	pm_runtime_put(vcm->sd.dev);

	return ret;
}

static const struct v4l2_ctrl_ops lc898217xc_ctrl_ops = {
	.s_ctrl = lc898217xc_set_ctrl,
};

static const struct v4l2_subdev_ops lc898217xc_subdev_ops = { };

static int lc898217xc_runtime_suspend(struct device *dev)
{
	struct v4l2_subdev *sd = dev_get_drvdata(dev);

	return lc898217xc_power_down(to_lc898217xc(sd));
}

static int lc898217xc_runtime_resume(struct device *dev)
{
	struct v4l2_subdev *sd = dev_get_drvdata(dev);

	return lc898217xc_power_up(to_lc898217xc(sd));
}

static int lc898217xc_probe(struct i2c_client *client)
{
	struct lc898217xc_device *vcm;
	u32 value;
	unsigned int i;
	int ret;

	vcm = devm_kzalloc(&client->dev, sizeof(*vcm), GFP_KERNEL);
	if (!vcm)
		return -ENOMEM;

	vcm->focus_pos_max = LC898217XC_MAX_FOCUS_POS;
	if (!device_property_read_u32(&client->dev,
				      "onnn,max-focus-position", &value)) {
		if (!value || value > LC898217XC_MAX_FOCUS_POS)
			return dev_err_probe(&client->dev, -EINVAL,
					     "invalid maximum focus position\n");
		vcm->focus_pos_max = value;
	}

	vcm->focus_pos_default = LC898217XC_DEFAULT_FOCUS_POS;
	if (!device_property_read_u32(&client->dev,
				      "onnn,default-focus-position", &value))
		vcm->focus_pos_default = value;
	if (vcm->focus_pos_default > vcm->focus_pos_max)
		return dev_err_probe(&client->dev, -EINVAL,
				     "default focus position exceeds maximum\n");

	for (i = 0; i < ARRAY_SIZE(lc898217xc_supply_names); i++)
		vcm->supplies[i].supply = lc898217xc_supply_names[i];

	ret = devm_regulator_bulk_get(&client->dev,
				      ARRAY_SIZE(lc898217xc_supply_names),
				      vcm->supplies);
	if (ret)
		return dev_err_probe(&client->dev, ret,
				     "failed to get regulators\n");

	v4l2_i2c_subdev_init(&vcm->sd, client, &lc898217xc_subdev_ops);
	device_disable_async_suspend(&client->dev);
	/*
	 * Opening the subdevice does not power the actuator: the sensor holds a
	 * runtime PM link to it, so the lens is driven only while the sensor is
	 * on. A position set meanwhile is kept and applied at power-up.
	 */
	vcm->sd.flags |= V4L2_SUBDEV_FL_HAS_DEVNODE;
	vcm->sd.entity.function = MEDIA_ENT_F_LENS;

	v4l2_ctrl_handler_init(&vcm->ctrls, 1);
	vcm->focus = v4l2_ctrl_new_std(&vcm->ctrls, &lc898217xc_ctrl_ops,
				       V4L2_CID_FOCUS_ABSOLUTE, 0,
				       vcm->focus_pos_max, 1,
				       vcm->focus_pos_default);
	if (vcm->ctrls.error) {
		ret = vcm->ctrls.error;
		goto err_free_ctrls;
	}
	vcm->sd.ctrl_handler = &vcm->ctrls;

	ret = media_entity_pads_init(&vcm->sd.entity, 0, NULL);
	if (ret)
		goto err_free_ctrls;

	ret = lc898217xc_power_up(vcm);
	if (ret) {
		dev_err_probe(&client->dev, ret,
			      "failed to power or identify actuator\n");
		goto err_cleanup_entity;
	}

	dev_info(&client->dev, "LC898217XC actuator ready\n");

	pm_runtime_set_active(&client->dev);
	pm_runtime_get_noresume(&client->dev);
	pm_runtime_enable(&client->dev);

	ret = v4l2_async_register_subdev(&vcm->sd);
	if (ret) {
		dev_err_probe(&client->dev, ret,
			      "failed to register V4L2 subdevice\n");
		goto err_pm;
	}

	pm_runtime_set_autosuspend_delay(&client->dev, 1000);
	pm_runtime_use_autosuspend(&client->dev);
	pm_runtime_put_autosuspend(&client->dev);

	return 0;

err_pm:
	pm_runtime_disable(&client->dev);
	pm_runtime_put_noidle(&client->dev);
	lc898217xc_power_down(vcm);
err_cleanup_entity:
	media_entity_cleanup(&vcm->sd.entity);
err_free_ctrls:
	v4l2_ctrl_handler_free(&vcm->ctrls);
	return ret;
}

static void lc898217xc_remove(struct i2c_client *client)
{
	struct v4l2_subdev *sd = i2c_get_clientdata(client);
	struct lc898217xc_device *vcm = to_lc898217xc(sd);

	v4l2_async_unregister_subdev(sd);
	v4l2_ctrl_handler_free(&vcm->ctrls);
	media_entity_cleanup(&sd->entity);

	pm_runtime_disable(&client->dev);
	if (!pm_runtime_status_suspended(&client->dev))
		lc898217xc_power_down(vcm);
	pm_runtime_set_suspended(&client->dev);
}

static const struct of_device_id lc898217xc_of_match[] = {
	{ .compatible = "onnn,lc898217xc" },
	{ }
};
MODULE_DEVICE_TABLE(of, lc898217xc_of_match);

static DEFINE_RUNTIME_DEV_PM_OPS(lc898217xc_pm_ops,
				 lc898217xc_runtime_suspend,
				 lc898217xc_runtime_resume, NULL);

static struct i2c_driver lc898217xc_i2c_driver = {
	.driver = {
		.name = "lc898217xc",
		.pm = pm_sleep_ptr(&lc898217xc_pm_ops),
		.of_match_table = lc898217xc_of_match,
	},
	.probe = lc898217xc_probe,
	.remove = lc898217xc_remove,
};
module_i2c_driver(lc898217xc_i2c_driver);

MODULE_AUTHOR("Sr-0w <Sr-0w@users.noreply.github.com>");
MODULE_DESCRIPTION("ON Semiconductor LC898217XC VCM driver");
MODULE_LICENSE("GPL");
