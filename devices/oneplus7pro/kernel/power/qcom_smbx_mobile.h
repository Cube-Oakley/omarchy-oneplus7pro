/* SPDX-License-Identifier: GPL-2.0-only */
/* Conservative PM8150b bring-up policy; included after the common helpers.
 * Standard power_supply readout, external gauge via DT reference. No Type-C
 * role changes, APSD reruns, fast-charge protocol or gauge-profile writes.
 */

static enum power_supply_property smb_mobile_properties[] = {
    POWER_SUPPLY_PROP_MANUFACTURER, POWER_SUPPLY_PROP_MODEL_NAME,
    POWER_SUPPLY_PROP_CURRENT_MAX, POWER_SUPPLY_PROP_STATUS,
    POWER_SUPPLY_PROP_HEALTH, POWER_SUPPLY_PROP_ONLINE,
    POWER_SUPPLY_PROP_USB_TYPE,
};

static int smb_mobile_write_verify(struct smb_chip *chip, unsigned int reg,
                                   unsigned int value)
{
    unsigned int actual;
    int ret = regmap_write(chip->regmap, chip->base + reg, value);
    if (ret)
        return ret;
    ret = regmap_read(chip->regmap, chip->base + reg, &actual);
    return ret ? ret : (actual == value ? 0 : -EIO);
}

static int smb_mobile_disable(struct smb_chip *chip)
{
    int ret = smb_mobile_write_verify(chip, CHARGING_ENABLE_CMD, 0);
    if (ret)
        dev_err_ratelimited(chip->dev, "Failed to disable charging: %d\n", ret);
    return ret;
}

static int smb_mobile_sample(struct smb_chip *chip, bool *allow)
{
    union power_supply_propval temp, voltage, amperage, present;
    unsigned int thermal, fault, path, fcc, fv, icl;
    int ret;

    *allow = false;
    if (chip->fault_latched)
        return -EIO;
    ret = power_supply_get_property(chip->fuel_gauge, POWER_SUPPLY_PROP_PRESENT, &present);
    if (ret || !present.intval)
        return ret ? ret : -ENODEV;
    ret = power_supply_get_property(chip->fuel_gauge, POWER_SUPPLY_PROP_TEMP, &temp);
    if (ret)
        return ret;
    ret = power_supply_get_property(chip->fuel_gauge, POWER_SUPPLY_PROP_VOLTAGE_NOW, &voltage);
    if (ret)
        return ret;
    ret = power_supply_get_property(chip->fuel_gauge, POWER_SUPPLY_PROP_CURRENT_NOW, &amperage);
    if (ret)
        return ret;
    if (regmap_read(chip->regmap, chip->base + BATTERY_CHARGER_STATUS_7, &thermal) ||
        regmap_read(chip->regmap, chip->base + BATTERY_CHARGER_STATUS_2, &fault) ||
        regmap_read(chip->regmap, chip->base + POWER_PATH_STATUS(chip), &path) ||
        regmap_read(chip->regmap, chip->base + FAST_CHARGE_CURRENT_CFG, &fcc) ||
        regmap_read(chip->regmap, chip->base + FLOAT_VOLTAGE_CFG, &fv) ||
        regmap_read(chip->regmap, chip->base + USBIN_CURRENT_LIMIT_CFG, &icl))
        return -EIO;
    /* PM8150b FCC/ICL are 50 mA/step; FV is 3.60 V + 10 mV/step. */
    if (fcc != 10 || fv != 60 || icl > 10 || amperage.intval > 650000 ||
        voltage.intval >= 4250000 || (fault & SMB5_CHARGER_ERROR_STATUS_BAT_OV_BIT)) {
        chip->fault_latched = true;
        dev_err(chip->dev, "Charge fault latched: FCC=%u FV=%u ICL=%u V=%d I=%d status=%02x\n",
                fcc, fv, icl, voltage.intval, amperage.intval, fault);
        return -ERANGE;
    }
    /* A missing input or thermal restriction is recoverable. No restart at
     * a temperature boundary: re-enable only in the narrower 12–38 C range.
     */
    if (temp.intval < (chip->charge_active ? 100 : 120) ||
        temp.intval >= (chip->charge_active ? 400 : 380) ||
        voltage.intval < 3000000 || voltage.intval >= 4220000 ||
        (thermal & 0x3f) || (path & 0x11) != 0x11 || (path & BIT(6)))
        return 0;
    *allow = true;
    return 0;
}

static void smb_mobile_work(struct work_struct *work)
{
    struct smb_chip *chip = container_of(work, struct smb_chip, status_change_work.work);
    bool allow;
    unsigned int command;
    int ret;

    mutex_lock(&chip->charge_lock);
    if (chip->stopping)
        goto out;
    ret = smb_mobile_sample(chip, &allow);
    if (ret)
        allow = false;
    /* Do not repeatedly issue enable commands to a running charge cycle.
     * Verify ownership before enabling or leaving charging enabled.
     */
    if (!allow) {
        ret = smb_mobile_disable(chip);
    } else {
        ret = regmap_read(chip->regmap, chip->base + CHARGING_ENABLE_CMD, &command);
        if (!ret && command != (chip->charge_active ? 1 : 0))
            ret = -EIO;
        if (!ret && !chip->charge_active)
            ret = smb_mobile_write_verify(chip, CHARGING_ENABLE_CMD, 1);
    }
    if (ret) {
        chip->fault_latched = true;
        smb_mobile_disable(chip);
        allow = false;
    }
    if (chip->charge_active != allow) {
        chip->charge_active = allow;
        dev_info(chip->dev, "Charging %s (500 mA, 4.20 V ceiling)\n", allow ? "enabled" : "disabled");
        power_supply_changed(chip->chg_psy);
    }
    schedule_delayed_work(&chip->status_change_work, msecs_to_jiffies(2000));
out:
    mutex_unlock(&chip->charge_lock);
}

static void smb_mobile_stop(void *data)
{
    struct smb_chip *chip = data;
    mutex_lock(&chip->charge_lock);
    chip->stopping = true;
    mutex_unlock(&chip->charge_lock);
    cancel_delayed_work_sync(&chip->status_change_work);
    smb_mobile_disable(chip);
    chip->charge_active = false;
    /* Leave the conservative FCC/FV limits in place, never raise them on exit. */
}

static void smb_mobile_put_info(void *data)
{
    struct smb_chip *chip = data;
    power_supply_put_battery_info(chip->chg_psy, chip->batt_info);
}

static int smb_mobile_probe(struct platform_device *pdev, struct smb_chip *chip)
{
    struct power_supply_config config = { .drv_data = chip, .fwnode = dev_fwnode(&pdev->dev) };
    struct power_supply_desc *desc;
    int ret;

    /* Disable even if a dependency defers probe. Configure all limits before
     * the monitoring worker can ever enable charging.
     */
    ret = smb_mobile_disable(chip);
    if (ret)
        return ret;
    chip->fuel_gauge = devm_power_supply_get_by_reference(chip->dev, "qcom,external-fuel-gauge");
    if (IS_ERR(chip->fuel_gauge))
        return dev_err_probe(chip->dev, PTR_ERR(chip->fuel_gauge), "External fuel gauge unavailable\n");
    if (!chip->fuel_gauge)
        return -EPROBE_DEFER;
    desc = devm_kmemdup(chip->dev, &smb_psy_desc, sizeof(*desc), GFP_KERNEL);
    if (!desc)
        return -ENOMEM;
    desc->name = "pm8150b-charger";
    desc->properties = smb_mobile_properties;
    desc->num_properties = ARRAY_SIZE(smb_mobile_properties);
    desc->set_property = NULL;
    desc->property_is_writeable = NULL;
    chip->chg_psy = devm_power_supply_register(chip->dev, desc, &config);
    if (IS_ERR(chip->chg_psy))
        return PTR_ERR(chip->chg_psy);
    ret = power_supply_get_battery_info(chip->chg_psy, &chip->batt_info);
    if (ret)
        return ret;
    ret = devm_add_action_or_reset(chip->dev, smb_mobile_put_info, chip);
    if (ret)
        return ret;
    if (chip->batt_info->constant_charge_current_max_ua != 500000 ||
        chip->batt_info->voltage_max_design_uv != 4200000)
        return dev_err_probe(chip->dev, -EINVAL, "Bring-up requires 500 mA / 4.20 V battery limits\n");
    ret = smb_mobile_write_verify(chip, FAST_CHARGE_CURRENT_CFG, 10);
    if (!ret)
        ret = smb_mobile_write_verify(chip, FLOAT_VOLTAGE_CFG, 60);
    if (!ret)
        ret = smb_mobile_write_verify(chip, USBIN_CURRENT_LIMIT_CFG, 10);
    if (ret)
        return ret;
    mutex_init(&chip->charge_lock);
    INIT_DELAYED_WORK(&chip->status_change_work, smb_mobile_work);
    ret = devm_add_action_or_reset(chip->dev, smb_mobile_stop, chip);
    if (ret)
        return ret;
    platform_set_drvdata(pdev, chip);
    schedule_delayed_work(&chip->status_change_work, 0);
    dev_info(chip->dev, "PM8150b guarded charging ready; 50 mA current / 10 mV float steps\n");
    return 0;
}

static int smb_mobile_suspend(struct device *dev)
{
    struct smb_chip *chip = dev_get_drvdata(dev);
    if (chip->gen == SMB5) {
        smb_mobile_stop(chip);
        return smb_mobile_disable(chip);
    }
    return 0;
}

static int smb_mobile_resume(struct device *dev)
{
    struct smb_chip *chip = dev_get_drvdata(dev);
    if (chip->gen == SMB5) {
        mutex_lock(&chip->charge_lock);
        chip->stopping = false;
        schedule_delayed_work(&chip->status_change_work, 0);
        mutex_unlock(&chip->charge_lock);
    }
    return 0;
}

static void smb_mobile_shutdown(struct platform_device *pdev)
{
    struct smb_chip *chip = platform_get_drvdata(pdev);
    if (chip && chip->gen == SMB5)
        smb_mobile_stop(chip);
}

static DEFINE_SIMPLE_DEV_PM_OPS(smb_mobile_pm, smb_mobile_suspend, smb_mobile_resume);
