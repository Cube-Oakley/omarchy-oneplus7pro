# USB gadget on this Pixel 7 Pro

Live Android (Evolution X + Magisk) owns USB through
`android.hardware.usb.gadget-service` (`sys.usb.configfs=2`).
Manual configfs writes are ignored while that HAL is running.

## Working controller

| | |
|---|---|
| UDC | `11210000.dwc3` (**never** `dummy_udc.0`) |
| Compatible | `samsung,exynos9-dwusb` |
| PHY | `11200000.phy` (`phy-exynos-usbdrd-super`) |
| Type-C TCPC | i2c `13-0025` (`tcpci_max77759`) |
| idVendor/idProduct (ADB) | `0x18d1` / `0x4ee7` |
| Gadget dir | `/config/usb_gadget/g1` |
| ACM function | `functions/acm.gs6` → `/dev/ttyGS0` |

Exynos glue sysfs (live Android values):

```
/sys/devices/platform/11210000.usb/usb_data_enabled = enabled
/sys/devices/platform/11210000.usb/dwc3_exynos_otg_id = 1
/sys/devices/platform/11210000.usb/dwc3_exynos_otg_b_sess = 1
/sys/devices/platform/11210000.usb/dwc3_exynos_otg_state = b_peripheral
/sys/devices/platform/11210000.usb/force_speed = super-speed-plus
```

`CONFIG_USB_DUMMY_HCD` is on. `/sys/class/udc` lists both
`11210000.dwc3` and `dummy_udc.0`. Binding the dummy UDC produces no
host device. Always bind `11210000.dwc3` by name.

## Proven on this unit (2026-09-08)

1. **RNDIS + ADB** (HAL path): `svc usb setFunctions rndis`
   enumerates as `18d1:4ee4` (tether+debug). `setprop sys.usb.config`
   does **not** switch functions on this ROM.
2. **ACM serial** (ramdisk-like path): `stop vendor.usb-gadget-hal`,
   unbind UDC, link only `acm.gs6`, bind `11210000.dwc3`.
   Host: `cdc_acm … ttyACM0`. Root shell `uid=0` on the serial port.
3. Adding ACM **while the HAL is running** leaves a configfs symlink
   but the host still sees only the ADB interface.

Persist is `/dev/block/sda1` → `/mnt/vendor/persist` and is writable
from Magisk root. Ramdisk `/init` should log to
`/persist/omarchy-ramdisk.log` (same partition).

## Why earlier ramdisks hung at the Google logo

- `/init` was a no-PIE C stub that `execve`'d Alpine **static-PIE**
  busybox **before** mounting `/dev` or setting SELinux permissive.
  Persist never got a log; USB never came up.
- `ls /sys/class/udc | head -1` can pick `dummy_udc.0`.
- Magisk busybox (NDK static **EXEC**, not PIE) is the ramdisk shell.

New image: `out/ramdisk-usb/init_boot-usb.img` (does not flash itself).
Restore: `scripts/restore-init-boot.sh`.

## 2026-09-09 flash (glibc /init + Magisk busybox)

Bootloader loaded our lz4 ramdisk (`1414694` bytes). Kernel log:

```
Run /init as init process
request_module fs-devtmpfs succeeded, but still no fs?
```

`CONFIG_DEVTMPFS is not set` on this 5.10 GKI. Persist log still missing
because `/dev/kmsg` and `/dev/sda1` never existed. Next ramdisk mounts
tmpfs on `/dev` and `mknod`s `kmsg` / `sda1` / `ttyGS0`.

## 2026-09-09 flash 2 (tmpfs + mknod)

`/init` ran. pstore:

```
OMARCHY: c-init mounts ok
OMARCHY: persist mount failed
OMARCHY: ko count=190
OMARCHY: ok phy-exynos-usbdrd-super.ko
OMARCHY: ok dwc3-exynos-usb.ko
OMARCHY: udc=dummy_udc.0
OMARCHY: otg_state=
```

PHY/DWC3 modules loaded but `11210000.dwc3` never probed. Missing
`exynos-pd.ko` (power domains; `modules.dep` has dwc3 → exynos-pd).
Also load s2mpg12/13 regulators. Persist mount is too early (UFS not
ready); retry after modules. Slot `_b` was repaired with `dd` of
`RESTORE-init_boot.img` after a failed fastboot write.

## 2026-09-09 flash 3 (exynos-pd)

`exynos-pd.ko` loaded; `pd-hsi0: on`. Then:

```
s2mpg12_regulator: Unknown symbol pmic_device_create
exynos_pd_hsi0: get vdd_hsi regulator failed: -517
udc=dummy_udc.0
```

`-517` is EPROBE_DEFER. `vdd_hsi` comes from s2mpg regulators, which need
`pmic_class.ko` **before** the regulator modules. Next image reorders that.

## 2026-09-09 flash 4 (pmic_class before s2mpg)

Regulators loaded and probed (`s2mpg12 i2c probe`, OCP_CTRL dumps).
UDC snapshot at t=1.06s still `dummy_udc.0` — i2c-exynos5 was loaded
*after* the regulator modules, so vdd_hsi appeared too late for the
immediate check. pstore was truncated before the 20s wait. Next image:
I2C → pmic → s2mpg → PHY/DWC3, then a 2s settle.

## 2026-09-09 flash 5 (I2C before regulators)

Modules through `google-cpm.ko` at t=1.04s. pstore then stops — no
`udc=` / gadget lines. The new `sleep 2` + persist remount sat *before*
gadget setup; a blocking `mount ext4 /dev/sda1` on a dead 8,1 node
likely stalled PID 1. Next image skips persist retry and logs UDC
immediately after the settle sleep.

## 2026-09-09 flash 7 (USB before persist)

pstore still ends at `ok google-cpm.ko` (t=1.05s). The next statement
is `$BB sleep 2`. Magisk busybox `sleep` likely never returns as PID 1
here, so gadget setup never runs. Next image waits via `/proc/uptime`
spin instead of `sleep`.

## 2026-09-09 flash 9 (uptime wait, clean pstore)

`wait_s` works. Timeline:

```
t=1.07  ok google-cpm.ko
t=3.04  udc=dummy_udc.0  otg_state=  usb_data=
t=23.04 udc_wait=none i=20 all=dummy_udc.0
t=23.05 ttyGS0=y  (mknod fake node — host sees nothing)
```

PHY/DWC3/exynos-pd/s2mpg all insert. `11210000.dwc3` never appears.
Platform `11210000.usb` sysfs is missing (`otg_state` empty). DWC3
module loaded but the controller did not probe.
