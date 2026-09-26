#!/usr/bin/env bash
# Flash OxygenOS 12 H.41 firmware images to both slots from bootloader.
# Does NOT touch userdata, boot, dtbo, or EFS (modemst).
set -euo pipefail
DIR="${1:-$(cd "$(dirname "$0")/../.work/firmware/oos12-h41/firmware-update" && pwd)}"
cd "$DIR"

flash_ab() {
  local part="$1" img="$2"
  echo ">>> $part <- $img"
  if fastboot flash --slot=all "$part" "$img"; then
    return 0
  fi
  echo "--slot=all failed for $part, flashing _a and _b"
  fastboot flash "${part}_a" "$img"
  fastboot flash "${part}_b" "$img"
}

# Order from LineageOS guacamole firmware wiki. xbl last.
flash_ab abl abl.img
flash_ab aop aop.img
flash_ab bluetooth bluetooth.img
flash_ab cmnlib64 cmnlib64.img
flash_ab cmnlib cmnlib.img
flash_ab devcfg devcfg.img
flash_ab dsp dsp.img
flash_ab hyp hyp.img
flash_ab keymaster keymaster.img
flash_ab LOGO LOGO.img
flash_ab modem modem.img
echo ">>> oem_stanvbk (no slots)"
fastboot flash oem_stanvbk oem_stanvbk.img
flash_ab qupfw qupfw.img
flash_ab storsec storsec.img
flash_ab tz tz.img
flash_ab xbl_config xbl_config.img
flash_ab xbl xbl.img
echo "firmware flash complete"
fastboot getvar unlocked
fastboot oem device-info || true
