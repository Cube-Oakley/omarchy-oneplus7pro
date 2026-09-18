/* SPDX-License-Identifier: GPL-2.0 */
/* Native5 diagnostic: release only MMCX's sleep clamp. ACTIVE/WAKE votes and
 * MSS/MX/CX remain governed by the original startup policy. Default off.
 * XO retains normal clock-framework operation from the verified DSI fix.
 * Setter updates the sleep cache only; it never sends an ACTIVE request.
 */
#include <linux/debugfs.h>

static bool mmcx_sleep_test_release;

static bool mmcx_sleep_test_domain(const struct rpmhpd *pd)
{
	return pd == &mmcx || pd == &mmcx_ao;
}

static int mmcx_sleep_test_get(void *unused, u64 *value)
{
	/* Remains readable if another RPMh operation is stalled. */
	*value = READ_ONCE(mmcx_sleep_test_release);
	return 0;
}

static int mmcx_sleep_test_set(void *unused, u64 value)
{
	struct rpmhpd *pd = &mmcx;
	unsigned int sleep_corner;
	int ret;

	if (value > 1)
		return -EINVAL;
	if (!mutex_trylock(&rpmhpd_lock))
		return -EBUSY;
	if (pd->state_synced || mmcx_ao.state_synced ||
	    !pd->dev || !pd->level_count || !pd->addr) {
		ret = -EBUSY;
		goto out;
	}
	/* Normal MMCX contributes its ordinary request; the active-only peer
	 * contributes zero to sleep. No voltage or corner index is invented.
	 */
	sleep_corner = value ? (pd->enabled ? max(pd->corner, pd->enable_corner) : 0)
			     : pd->level_count - 1;
	ret = rpmhpd_send_corner(pd, RPMH_SLEEP_STATE, sleep_corner, false);
	if (!ret) {
		WRITE_ONCE(mmcx_sleep_test_release, !!value);
		dev_info(pd->dev, "MMCX sleep diagnostic release=%llu cached_sleep_corner=%u; ACTIVE/WAKE and other domains unchanged\n",
			 value, sleep_corner);
	}
out:
	mutex_unlock(&rpmhpd_lock);
	return ret;
}
DEFINE_DEBUGFS_ATTRIBUTE(mmcx_sleep_test_fops, mmcx_sleep_test_get, mmcx_sleep_test_set, "%llu\n");

static void mmcx_sleep_test_init(struct device *dev)
{
	if (of_machine_is_compatible("oneplus,guacamole") &&
	    of_device_is_compatible(dev->of_node, "qcom,sm8150-rpmhpd"))
		debugfs_create_file("guacamole_mmcx_sleep_release", 0600, NULL,
				    NULL, &mmcx_sleep_test_fops);
}
