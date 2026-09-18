// SPDX-License-Identifier: GPL-2.0-only
/*
 * Read-only identification support for the NXP TFA9874 amplifier.
 *
 * Output control remains deliberately absent until the external protection
 * profile and shared reset-line handling are implemented.
 */

#include <linux/i2c.h>
#include <linux/module.h>
#include <linux/regmap.h>
#include <sound/soc.h>

#define TFA9874_REVISION_REG	0x03
#define TFA9874_REVISION_0C74	0x0c74

static bool tfa9874_readable_reg(struct device *dev, unsigned int reg)
{
	return reg == TFA9874_REVISION_REG;
}

static bool tfa9874_writeable_reg(struct device *dev, unsigned int reg)
{
	return false;
}

static const struct regmap_config tfa9874_regmap_config = {
	.reg_bits = 8,
	.val_bits = 16,
	.val_format_endian = REGMAP_ENDIAN_BIG,
	.max_register = TFA9874_REVISION_REG,
	.readable_reg = tfa9874_readable_reg,
	.writeable_reg = tfa9874_writeable_reg,
	.cache_type = REGCACHE_NONE,
};

static const struct snd_soc_component_driver tfa9874_component_driver = {
	.name = "tfa9874",
};

static int tfa9874_i2c_probe(struct i2c_client *client)
{
	struct regmap *regmap;
	unsigned int revision;
	int ret;

	regmap = devm_regmap_init_i2c(client, &tfa9874_regmap_config);
	if (IS_ERR(regmap))
		return dev_err_probe(&client->dev, PTR_ERR(regmap),
				     "failed to allocate register map\n");

	ret = regmap_read(regmap, TFA9874_REVISION_REG, &revision);
	if (ret)
		return dev_err_probe(&client->dev, ret,
				     "failed to read silicon revision\n");

	if (revision != TFA9874_REVISION_0C74) {
		dev_err(&client->dev, "unsupported silicon revision 0x%04x\n",
			revision);
		return -ENODEV;
	}

	dev_info(&client->dev,
		 "TFA9874 revision 0x%04x detected; amplifier remains disabled\n",
		 revision);

	return devm_snd_soc_register_component(&client->dev,
					       &tfa9874_component_driver,
					       NULL, 0);
}

static const struct of_device_id tfa9874_of_match[] = {
	{ .compatible = "nxp,tfa9874" },
	{}
};
MODULE_DEVICE_TABLE(of, tfa9874_of_match);

static const struct i2c_device_id tfa9874_i2c_id[] = {
	{ "tfa9874" },
	{}
};
MODULE_DEVICE_TABLE(i2c, tfa9874_i2c_id);

static struct i2c_driver tfa9874_i2c_driver = {
	.driver = {
		.name = "tfa9874",
		.of_match_table = tfa9874_of_match,
	},
	.probe = tfa9874_i2c_probe,
	.id_table = tfa9874_i2c_id,
};
module_i2c_driver(tfa9874_i2c_driver);

MODULE_DESCRIPTION("Read-only NXP TFA9874 amplifier identification driver");
MODULE_AUTHOR("Robin Snyders <robin@snyders.xyz>");
MODULE_LICENSE("GPL");
