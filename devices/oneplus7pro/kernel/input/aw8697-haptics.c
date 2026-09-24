// SPDX-License-Identifier: GPL-2.0-only
/*
 * Awinic AW8697 LRA haptics controller
 *
 * Register programming is based on the AW8697 driver published by OnePlus.
 * The input force-feedback interface follows the upstream AW86927 driver.
 *
 * From the OnePlus 7T Pro port (Robin Snyders, hotdog-linux-bringup, 0130),
 * built here as an out-of-tree module. The OnePlus 7 Pro's stock tree gives
 * the part device id 619, for which the stock driver uses the same 170 Hz
 * "0815" profile as the 7T Pro: the constants below are those values.
 */

#include <linux/bits.h>
#include <linux/delay.h>
#include <linux/gpio/consumer.h>
#include <linux/i2c.h>
#include <linux/input.h>
#include <linux/module.h>
#include <linux/regmap.h>

#define AW8697_ID_REG			0x00
#define AW8697_CHIP_ID			0x97
#define AW8697_SOFT_RESET		0xaa

#define AW8697_SYSINT_REG		0x02
#define AW8697_SYSINTM_REG		0x03
#define AW8697_SYSCTRL_REG		0x04
#define AW8697_SYSCTRL_PLAY_MODE_MASK	GENMASK(3, 2)
#define AW8697_SYSCTRL_PLAY_MODE_CONT	(2 << 2)
#define AW8697_SYSCTRL_BST_MODE_MASK	BIT(1)
#define AW8697_SYSCTRL_WORK_MODE_MASK	BIT(0)
#define AW8697_SYSCTRL_STANDBY		BIT(0)
#define AW8697_GO_REG			0x05
#define AW8697_GO_ENABLE			BIT(0)

#define AW8697_DATCTRL_REG		0x2b
#define AW8697_DATCTRL_FC_MASK		GENMASK(7, 6)
#define AW8697_DATCTRL_FC_1000HZ		(3 << 6)
#define AW8697_DATCTRL_LPF_ENABLE	BIT(5)
#define AW8697_PWMDBG_REG		0x2e
#define AW8697_PWMDBG_MODE_MASK		GENMASK(6, 5)
#define AW8697_PWMDBG_24KHZ		(2 << 5)
#define AW8697_BSTDBG1_REG		0x31
#define AW8697_BSTDBG2_REG		0x32
#define AW8697_BSTDBG3_REG		0x33
#define AW8697_BSTCFG_REG		0x34
#define AW8697_BSTCFG_PEAK_MASK		GENMASK(2, 0)
#define AW8697_BSTCFG_PEAK_3P5A		5
#define AW8697_ANADBG_REG		0x35
#define AW8697_ANADBG_IOC_MASK		GENMASK(3, 2)
#define AW8697_ANADBG_IOC_4P65A		(3 << 2)
#define AW8697_BST_AUTO_REG		0x47
#define AW8697_BST_AUTO_AUTOSW		BIT(2)

#define AW8697_GLB_STATE_REG		0x46
#define AW8697_GLB_STATE_MASK		GENMASK(3, 0)
#define AW8697_CONT_CTRL_REG		0x48
#define AW8697_CONT_ZC_ENABLE		BIT(7)
#define AW8697_CONT_CLOSE_PLAYBACK	BIT(3)
#define AW8697_CONT_AUTO_BRAKE		BIT(0)
#define AW8697_F_PRE_H_REG		0x49
#define AW8697_F_PRE_L_REG		0x4a
#define AW8697_TD_H_REG			0x4b
#define AW8697_TD_L_REG			0x4c
#define AW8697_TSET_REG			0x4d
#define AW8697_R_SPARE_REG		0x5d
#define AW8697_ADCTEST_REG		0x66
#define AW8697_ADCTEST_VBAT_HW_COMP	BIT(6)
#define AW8697_ZC_THRSH_H_REG		0x72
#define AW8697_ZC_THRSH_L_REG		0x73
#define AW8697_BEMF_VTHH_H_REG		0x74
#define AW8697_BEMF_VTHH_L_REG		0x75
#define AW8697_BEMF_VTHL_H_REG		0x76
#define AW8697_BEMF_VTHL_L_REG		0x77
#define AW8697_BEMF_NUM_REG		0x78
#define AW8697_BEMF_NUM_BRAKE_MASK	GENMASK(3, 0)
#define AW8697_TIME_NZC_REG		0x7a
#define AW8697_DRV_LVL_REG		0x7b
#define AW8697_DRV_LVL_OV_REG		0x7c

/* OnePlus hotdog uses the 170 Hz actuator profile. */
#define AW8697_F0_PRE			1700
#define AW8697_F0_COEFF			260
#define AW8697_CONT_DRV_LVL_MAX		60
#define AW8697_CONT_DRV_LVL_OV		125
#define AW8697_CONT_TD			0x009a
#define AW8697_CONT_ZC_THR		0x0ff1
#define AW8697_CONT_BRAKE_COUNT		3

struct aw8697_haptics {
	struct device *dev;
	struct input_dev *input;
	struct regmap *regmap;
	struct gpio_desc *reset_gpio;
	struct work_struct play_work;
	u16 level;
};

static const struct regmap_config aw8697_regmap_config = {
	.reg_bits = 8,
	.val_bits = 8,
	.max_register = AW8697_DRV_LVL_OV_REG,
	.cache_type = REGCACHE_NONE,
};

static void aw8697_hw_reset(struct aw8697_haptics *haptics)
{
	gpiod_set_value_cansleep(haptics->reset_gpio, 1);
	usleep_range(1000, 2000);
	gpiod_set_value_cansleep(haptics->reset_gpio, 0);
	usleep_range(8000, 8500);
}

static int aw8697_wait_standby(struct aw8697_haptics *haptics)
{
	unsigned int value;

	return regmap_read_poll_timeout(haptics->regmap, AW8697_GLB_STATE_REG,
					value,
					!(value & AW8697_GLB_STATE_MASK),
					2000, 120000);
}

static int aw8697_stop(struct aw8697_haptics *haptics)
{
	int error;

	error = regmap_update_bits(haptics->regmap, AW8697_GO_REG,
				   AW8697_GO_ENABLE, 0);
	if (error)
		return error;

	error = aw8697_wait_standby(haptics);
	if (error)
		dev_warn(haptics->dev,
			 "playback did not stop cleanly, forcing standby\n");

	return regmap_update_bits(haptics->regmap, AW8697_SYSCTRL_REG,
				  AW8697_SYSCTRL_WORK_MODE_MASK,
				  AW8697_SYSCTRL_STANDBY);
}

static int aw8697_play_continuous(struct aw8697_haptics *haptics)
{
	unsigned int sysint;
	u16 f0_reg = 1000000000U / (AW8697_F0_PRE * AW8697_F0_COEFF);
	u8 drive_level;
	int error;

	error = aw8697_stop(haptics);
	if (error)
		return error;

	drive_level = DIV_ROUND_UP((u32)haptics->level *
				   AW8697_CONT_DRV_LVL_MAX, U16_MAX);

	error = regmap_update_bits(haptics->regmap, AW8697_SYSCTRL_REG,
				   AW8697_SYSCTRL_PLAY_MODE_MASK |
				   AW8697_SYSCTRL_BST_MODE_MASK |
				   AW8697_SYSCTRL_WORK_MODE_MASK,
				   AW8697_SYSCTRL_PLAY_MODE_CONT);
	if (error)
		return error;

	/* Reading SYSINT clears any latched interrupt before playback. */
	regmap_read(haptics->regmap, AW8697_SYSINT_REG, &sysint);

	error = regmap_update_bits(haptics->regmap, AW8697_DATCTRL_REG,
				   AW8697_DATCTRL_FC_MASK |
				   AW8697_DATCTRL_LPF_ENABLE,
				   AW8697_DATCTRL_FC_1000HZ |
				   AW8697_DATCTRL_LPF_ENABLE);
	if (error)
		return error;

	error = regmap_write(haptics->regmap, AW8697_CONT_CTRL_REG,
			     AW8697_CONT_ZC_ENABLE |
			     AW8697_CONT_CLOSE_PLAYBACK |
			     AW8697_CONT_AUTO_BRAKE);
	if (error)
		return error;

	error = regmap_write(haptics->regmap, AW8697_F_PRE_H_REG, f0_reg >> 8);
	if (error)
		return error;
	error = regmap_write(haptics->regmap, AW8697_F_PRE_L_REG, f0_reg);
	if (error)
		return error;
	error = regmap_write(haptics->regmap, AW8697_TD_H_REG, AW8697_CONT_TD >> 8);
	if (error)
		return error;
	error = regmap_write(haptics->regmap, AW8697_TD_L_REG, AW8697_CONT_TD);
	if (error)
		return error;
	error = regmap_write(haptics->regmap, AW8697_TSET_REG, 0x12);
	if (error)
		return error;
	error = regmap_write(haptics->regmap, AW8697_ZC_THRSH_H_REG,
			     AW8697_CONT_ZC_THR >> 8);
	if (error)
		return error;
	error = regmap_write(haptics->regmap, AW8697_ZC_THRSH_L_REG,
			     AW8697_CONT_ZC_THR);
	if (error)
		return error;

	error = regmap_write(haptics->regmap, AW8697_BEMF_VTHH_H_REG, 0x10);
	if (error)
		return error;
	error = regmap_write(haptics->regmap, AW8697_BEMF_VTHH_L_REG, 0x08);
	if (error)
		return error;
	error = regmap_write(haptics->regmap, AW8697_BEMF_VTHL_H_REG, 0x03);
	if (error)
		return error;
	error = regmap_write(haptics->regmap, AW8697_BEMF_VTHL_L_REG, 0xf8);
	if (error)
		return error;
	error = regmap_update_bits(haptics->regmap, AW8697_BEMF_NUM_REG,
				   AW8697_BEMF_NUM_BRAKE_MASK,
				   AW8697_CONT_BRAKE_COUNT);
	if (error)
		return error;
	error = regmap_write(haptics->regmap, AW8697_TIME_NZC_REG, 0x23);
	if (error)
		return error;
	error = regmap_write(haptics->regmap, AW8697_DRV_LVL_REG, drive_level);
	if (error)
		return error;
	error = regmap_write(haptics->regmap, AW8697_DRV_LVL_OV_REG,
			     AW8697_CONT_DRV_LVL_OV);
	if (error)
		return error;

	return regmap_update_bits(haptics->regmap, AW8697_GO_REG,
				  AW8697_GO_ENABLE, AW8697_GO_ENABLE);
}

static void aw8697_play_work(struct work_struct *work)
{
	struct aw8697_haptics *haptics =
		container_of(work, struct aw8697_haptics, play_work);
	int error;

	if (haptics->level)
		error = aw8697_play_continuous(haptics);
	else
		error = aw8697_stop(haptics);

	if (error)
		dev_err(haptics->dev, "failed to update playback: %d\n", error);
}

static int aw8697_play_effect(struct input_dev *input, void *data,
			      struct ff_effect *effect)
{
	struct aw8697_haptics *haptics = input_get_drvdata(input);
	u16 level = effect->u.rumble.strong_magnitude;

	if (!level)
		level = effect->u.rumble.weak_magnitude;
	if (level == haptics->level)
		return 0;

	haptics->level = level;
	schedule_work(&haptics->play_work);

	return 0;
}

static void aw8697_input_close(struct input_dev *input)
{
	struct aw8697_haptics *haptics = input_get_drvdata(input);

	haptics->level = 0;
	cancel_work_sync(&haptics->play_work);
	if (aw8697_stop(haptics))
		dev_warn(haptics->dev, "failed to stop haptics on close\n");
}

static int aw8697_init(struct aw8697_haptics *haptics)
{
	int error;

	error = aw8697_stop(haptics);
	if (error)
		return error;

	error = regmap_update_bits(haptics->regmap, AW8697_PWMDBG_REG,
				   AW8697_PWMDBG_MODE_MASK, AW8697_PWMDBG_24KHZ);
	if (error)
		return error;

	error = regmap_write(haptics->regmap, AW8697_BSTDBG1_REG, 0x30);
	if (error)
		return error;
	error = regmap_write(haptics->regmap, AW8697_BSTDBG2_REG, 0xeb);
	if (error)
		return error;
	error = regmap_write(haptics->regmap, AW8697_BSTDBG3_REG, 0xd4);
	if (error)
		return error;
	error = regmap_write(haptics->regmap, AW8697_TSET_REG, 0x12);
	if (error)
		return error;
	error = regmap_write(haptics->regmap, AW8697_R_SPARE_REG, 0x68);
	if (error)
		return error;

	error = regmap_update_bits(haptics->regmap, AW8697_ANADBG_REG,
				   AW8697_ANADBG_IOC_MASK,
				   AW8697_ANADBG_IOC_4P65A);
	if (error)
		return error;
	error = regmap_update_bits(haptics->regmap, AW8697_BSTCFG_REG,
				   AW8697_BSTCFG_PEAK_MASK,
				   AW8697_BSTCFG_PEAK_3P5A);
	if (error)
		return error;
	error = regmap_update_bits(haptics->regmap, AW8697_BST_AUTO_REG,
				   AW8697_BST_AUTO_AUTOSW, 0);
	if (error)
		return error;

	return regmap_update_bits(haptics->regmap, AW8697_ADCTEST_REG,
				  AW8697_ADCTEST_VBAT_HW_COMP,
				  AW8697_ADCTEST_VBAT_HW_COMP);
}

static int aw8697_probe(struct i2c_client *client)
{
	struct aw8697_haptics *haptics;
	unsigned int chip_id;
	int error;

	haptics = devm_kzalloc(&client->dev, sizeof(*haptics), GFP_KERNEL);
	if (!haptics)
		return -ENOMEM;

	haptics->dev = &client->dev;
	haptics->regmap = devm_regmap_init_i2c(client, &aw8697_regmap_config);
	if (IS_ERR(haptics->regmap))
		return dev_err_probe(&client->dev, PTR_ERR(haptics->regmap),
				     "failed to initialize regmap\n");

	haptics->reset_gpio = devm_gpiod_get(&client->dev, "reset", GPIOD_OUT_HIGH);
	if (IS_ERR(haptics->reset_gpio))
		return dev_err_probe(&client->dev, PTR_ERR(haptics->reset_gpio),
				     "failed to request reset GPIO\n");

	aw8697_hw_reset(haptics);
	error = regmap_read(haptics->regmap, AW8697_ID_REG, &chip_id);
	if (error)
		return dev_err_probe(&client->dev, error, "failed to read chip ID\n");
	if (chip_id != AW8697_CHIP_ID)
		return dev_err_probe(&client->dev, -ENODEV,
				     "unexpected chip ID 0x%02x\n", chip_id);

	error = regmap_write(haptics->regmap, AW8697_ID_REG, AW8697_SOFT_RESET);
	if (error)
		return dev_err_probe(&client->dev, error, "software reset failed\n");
	usleep_range(3000, 3500);

	INIT_WORK(&haptics->play_work, aw8697_play_work);
	haptics->input = devm_input_allocate_device(&client->dev);
	if (!haptics->input)
		return -ENOMEM;

	haptics->input->name = "Awinic AW8697 haptics";
	haptics->input->close = aw8697_input_close;
	input_set_drvdata(haptics->input, haptics);
	input_set_capability(haptics->input, EV_FF, FF_RUMBLE);

	error = input_ff_create_memless(haptics->input, NULL, aw8697_play_effect);
	if (error)
		return dev_err_probe(&client->dev, error,
				     "failed to create force-feedback device\n");

	error = aw8697_init(haptics);
	if (error)
		return dev_err_probe(&client->dev, error,
				     "failed to initialize haptics controller\n");

	i2c_set_clientdata(client, haptics);
	error = input_register_device(haptics->input);
	if (error)
		return dev_err_probe(&client->dev, error,
				     "failed to register input device\n");

	dev_info(&client->dev, "AW8697 haptics controller detected\n");
	return 0;
}

static void aw8697_remove(struct i2c_client *client)
{
	struct aw8697_haptics *haptics = i2c_get_clientdata(client);

	haptics->level = 0;
	cancel_work_sync(&haptics->play_work);
	aw8697_stop(haptics);
}

static const struct of_device_id aw8697_of_match[] = {
	{ .compatible = "awinic,aw8697" },
	{ }
};
MODULE_DEVICE_TABLE(of, aw8697_of_match);

static struct i2c_driver aw8697_driver = {
	.driver = {
		.name = "aw8697-haptics",
		.of_match_table = aw8697_of_match,
	},
	.probe = aw8697_probe,
	.remove = aw8697_remove,
};
module_i2c_driver(aw8697_driver);

MODULE_AUTHOR("Robin Snyders <robin@snyders.xyz>");
MODULE_DESCRIPTION("Awinic AW8697 LRA haptics driver");
MODULE_LICENSE("GPL");
