/* SPDX-License-Identifier: GPL-2.0 */
/* Native5 diagnostic: release only CX's sleep clamp. ACTIVE/WAKE votes and
 * MSS/MX/MMCX/XO remain governed by the original startup policy. Default off.
 * Setter updates the sleep cache only; it never sends an ACTIVE request.
 */
#include <linux/debugfs.h>

static bool cx_sleep_test_release;

static bool cx_sleep_test_domain(const struct rpmhpd *pd)
{
	return pd == &cx_w_mx_parent || pd == &cx_ao_w_mx_parent;
}

static int cx_sleep_test_get(void *unused, u64 *value)
{
	/* Remains readable if another RPMh operation is stalled. */
	*value = READ_ONCE(cx_sleep_test_release);
	return 0;
}

static int cx_sleep_test_set(void *unused, u64 value)
{
	struct rpmhpd *pd = &cx_w_mx_parent;
	unsigned int sleep_corner;
	int ret;

	if (value > 1)
		return -EINVAL;
	if (!mutex_trylock(&rpmhpd_lock))
		return -EBUSY;
	if (pd->state_synced || cx_ao_w_mx_parent.state_synced ||
	    !pd->dev || !pd->level_count || !pd->addr) {
		ret = -EBUSY;
		goto out;
	}
	/* Normal CX contributes its ordinary request; the active-only peer
	 * contributes zero to sleep. No voltage or corner index is invented.
	 */
	sleep_corner = value ? (pd->enabled ? max(pd->corner, pd->enable_corner) : 0)
			     : pd->level_count - 1;
	ret = rpmhpd_send_corner(pd, RPMH_SLEEP_STATE, sleep_corner, false);
	if (!ret) {
		WRITE_ONCE(cx_sleep_test_release, !!value);
		dev_info(pd->dev, "CX sleep diagnostic release=%llu cached_sleep_corner=%u; ACTIVE/WAKE and other domains unchanged\n",
			 value, sleep_corner);
	}
out:
	mutex_unlock(&rpmhpd_lock);
	return ret;
}
DEFINE_DEBUGFS_ATTRIBUTE(cx_sleep_test_fops, cx_sleep_test_get, cx_sleep_test_set, "%llu\n");

static void cx_sleep_test_init(struct device *dev)
{
	if (of_machine_is_compatible("oneplus,guacamole") &&
	    of_device_is_compatible(dev->of_node, "qcom,sm8150-rpmhpd"))
		debugfs_create_file("guacamole_cx_sleep_release", 0600, NULL,
				    NULL, &cx_sleep_test_fops);
}
