/* SPDX-License-Identifier: GPL-2.0 */
/* Diagnostic native5 variant only. Included after the normal RPMh domains.
 * Default zero preserves existing handoff policy. Does not enable CAMCC,
 * complete global sync_state, select a voltage, or modify other domains.
 */
#include <linux/debugfs.h>

static bool mss_test_release;
static int rpmhpd_aggregate_corner(struct rpmhpd *pd, unsigned int corner);

static int mss_test_get(void *unused, u64 *value)
{
	mutex_lock(&rpmhpd_lock);
	*value = mss_test_release;
	mutex_unlock(&rpmhpd_lock);
	return 0;
}

static int mss_test_set(void *unused, u64 value)
{
	unsigned int corner, before;
	bool old;
	int ret, restore;

	if (value > 1)
		return -EINVAL;
	mutex_lock(&rpmhpd_lock);
	/* This test only isolates the unsynchronized startup hold. */
	if (mss.state_synced || !mss.dev || !mss.level_count) {
		ret = -EBUSY;
		goto out;
	}
	old = mss_test_release;
	before = mss.active_corner;
	mss_test_release = value;
	corner = mss.enabled ? max(mss.corner, mss.enable_corner) : 0;
	ret = rpmhpd_aggregate_corner(&mss, corner);
	if (ret) {
		mss_test_release = old;
		restore = rpmhpd_aggregate_corner(&mss, corner);
		dev_err(mss.dev, "MSS diagnostic failed=%d restore=%d\n", ret, restore);
	} else {
		dev_info(mss.dev, "MSS diagnostic release=%llu active_corner=%u->%u; other handoff policy unchanged\n",
			 value, before, mss.active_corner);
	}
out:
	mutex_unlock(&rpmhpd_lock);
	return ret;
}
DEFINE_DEBUGFS_ATTRIBUTE(mss_test_fops, mss_test_get, mss_test_set, "%llu\n");

static void mss_test_init(struct device *dev)
{
	if (of_machine_is_compatible("oneplus,guacamole") &&
	    of_device_is_compatible(dev->of_node, "qcom,sm8150-rpmhpd"))
		debugfs_create_file("guacamole_mss_handoff_release", 0600, NULL,
				    NULL, &mss_test_fops);
}
