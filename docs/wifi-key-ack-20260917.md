# WCN3990 key acknowledgement investigation — 2026-09-17

Native5 #184, same verified boot. The initial Power trials all incurred about
three seconds between deauthentication and key-removal error -110. The same
error occurred during roaming, so it is not confined to PM callback ordering.

## Evidence and diagnosis

A scoped `debug_mask=10` probe enables WMI and HTT metadata, without packet/key
dump masks. It disconnects/reconnects only wlan0 while USB stays available and
restores the previous debug mask in finally. No credentials are read.

The original module logged:

- 1779.306663: WMI key removal sent.
- 1779.308821: WMI_VDEV_INSTALL_KEY_COMPLETE_EVENTID received (2.16 ms later).
- 1782.328943: install-key wait returns -110; no HTT SEC_IND arrived for removal.

`ath10k_install_key()` waits for `install_key_done`, signalled by HTT SEC_IND.
The existing WMI key-completion handler only prints a debug message. New key
installation emits both HTT SEC_IND and WMI completion; deletion emits WMI
completion in this trial. Thus a real acknowledgement is already available.

Related upstream [RFC](https://www.mail-archive.com/ath10k%40lists.infradead.org/msg17566.html)
proposes skipping deletion waits. [Review discussion](https://www.mail-archive.com/ath10k%40lists.infradead.org/msg17572.html)
questions late responses being mistaken for subsequent installations. This
experiment instead consumes WMI acknowledgements for both operations. The
payload layout follows Qualcomm's
[wmi_unified.h](https://android.googlesource.com/kernel/msm.git/+/f6da9680a25d881411386981a92a35bfa4c5b049/drivers/staging/qcacld-2.0/CORE/SERVICES/COMMON/wmi_unified.h).

## Isolated test implementation

`devices/oneplus7pro/kernel/radio/ath10k-snoc-key-ack.patch` adds a separate
completion for SNOC/TLV only. It matches vdev, peer address, key index and flags,
checks firmware status, and preserves the HTT security/PN wait for key installs.
Deletion waits for its WMI acknowledgement. Pending metadata uses data_lock;
operations remain serialized by conf_mutex. Parser minimum lengths are checked.
An ambiguous command/response failure marks the sequence unusable until firmware
restart, so a timed-out response cannot satisfy a later operation. Other bus
key-install paths retain their existing HTT wait.

`scripts/build_wifi_key_ack_test.sh` copies sources into `.work/wifi-key-ack`,
applies the patch and builds against native5 with exact dependency symbol tables.
The first link attempt lacked the remoteproc symbol table; supplying it fixed
the unresolved SSR notifier symbols. No unresolved-symbol suppression is used.
Both ath10k_core and ath10k_snoc must be replaced together because the internal
ath10k structure changed. No other radio modules or modem firmware are changed.

## Live results and suspend validation

The version-matched pair is live from `/root/wifi-key-ack-test/`. Reload was
protected by an error trap restoring the original pair if loading, association
or HTTPS failed. Modem/RMTFS remained running. Original boot module files were unchanged during live tests; the approved
persistent promotion described below has now installed the tested pair.

Same awake disconnect test: **3.399 s original → 0.391 s patched**. The patched
trace confirms removal acknowledged in 2.15 ms with status 0, and both new keys
receive WMI and HTT responses. No key-removal timeout occurred. Reconnection
took 13.54 seconds (original 14.24); scanning/association/address setup are
separate from the removed key timeout. HTTPS after load and after the trial
passed. Debug mask is restored to zero.

Evidence: `out/wifi-sleep-delay/`; modules/patch/hashes: `out/wifi-key-ack/`.
Core SHA256: `f5e3ff33c5f9b5ccc9ea7a454d56db944e870114068933ecf516698e6b22541b`.
SNOC SHA256: `65d924cfd47ac7ec029edb4fdc0ff8820df79522e86cb87a1cdfcacf28198ddb`.

The five-minute unplugged trial subsequently passed: 301.12 seconds asleep,
zero PM failures, input recovery and Wi-Fi HTTPS. The key-removal timeout is
absent in suspend and a later roam. Deauthentication to the following USB PM
message was about 0.230 seconds, versus the former three-second key wait.
See [idle results](idle-measurement-20260917.md).
This is a local experimental fix, not an upstream-accepted patch. Repeated
roaming/rekey and error-recovery coverage remain limited.

## Recovery

Before persistent promotion, reboot used the original pair. After promotion,
restore the preserved complete `.before-key-ack` directory to return to the
original pair on subsequent boot. Live restoration: disconnect wlan0,
unload ath10k_snoc then ath10k_core, insert the original pair from
`/root/radio-bringup/modules/$(uname -r).before-key-ack/`, wait for wlan0, reactivate the saved
profile. Never unload the modem or stop RMTFS for this Wi-Fi-only test.

## Persistent installation approved and completed

`scripts/phone-install-wifi-key-ack.py` is the concrete prepared promotion. It
requires exact native5 release and the two tested module SHA256s, validates the
original manifest, stages a complete dependency directory, validates every
vermagic and new hash, then atomically exchanges directories using
RENAME_EXCHANGE. Original modules are retained in the sibling directory ending
`.before-key-ack`. Running modules and boot partitions are untouched. Rollback
can restore that full original directory; an unexpected boot-time Wi-Fi
regression remains possible until the next reboot is verified.

The future native5 build recipe now selects RADIO_KEY_ACK=1; the generic radio
builder applies the same patch only when explicitly requested. Syntax checks
and Python compilation pass. No new build or flash was performed here.

Automatic approval review initially rejected the promotion as beyond explicit
user authorization. The user then explicitly approved installing the Wi-Fi fix.
The prepared installer completed successfully, atomically promoting the full
version-matched directory. Final hashes match both tested modules; all dependency
manifest checks pass. Backup is the complete directory ending `.before-key-ack`.
Wi-Fi HTTPS, modem and charging remain healthy, debug mask is zero.

Evidence: `persistent-install.log` and `persistent-verification.log` under
`out/wifi-sleep-delay/`. No boot partition was flashed and no reboot occurred.
**Automatic use of the new on-disk pair passed the later recovery reboot.**
Boot `927a5e82-e6ae-4efc-9123-80844ecf186b` loaded the checksummed module
directory, started MPSS and connected test-network automatically; Wi-Fi HTTPS 200
passed with debug mask 0 and no host service repair. Evidence:
`out/sleep-stats/recovered-{boot,network}.log`. A separate temporary CAMCC
power-domain experiment caused a modem watchdog on suspend in the preceding
boot; that experiment was discarded. The key-ack fix remains installed.
Checkpoint: `out/checkpoints/20260917-wifi-key-ack-verified/`.
