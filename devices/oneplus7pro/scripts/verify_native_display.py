#!/usr/bin/env python3
"""Verify current native display packaging and recovery inputs; no phone access."""
from pathlib import Path
import gzip
import subprocess
import tempfile
import argparse
import os

ROOT = Path(__file__).resolve().parents[1]
OUT = Path(os.environ.get("NATIVE_OUTPUT", ROOT / "out/native-display-test"))
SRC = Path(os.environ.get("NATIVE_KERNEL_TREE", ROOT / ".work/linux-sm8150-codex-native"))
BASE = ROOT / "out/checkpoints/20260916-touch1/embedded.dtb"


def fdt(dtb, *args):
    return subprocess.check_output(["fdtget", *args[:1], str(dtb), *args[1:]], text=True).strip()


def subtree(dtb, path):
    result = {}
    for prop in fdt(dtb, "-p", path).splitlines():
        result[path + "/" + prop] = fdt(dtb, "-tx", path, prop)
    for child in fdt(dtb, "-l", path).splitlines():
        result.update(subtree(dtb, path + "/" + child))
    return result


def newc_files(data):
    files = {}
    pos = 0
    while pos < len(data):
        assert data[pos:pos + 6] == b"070701", "Invalid newc archive"
        fields = [int(data[pos + 6 + i * 8:pos + 14 + i * 8], 16) for i in range(13)]
        size, namesize = fields[6], fields[11]
        name = data[pos + 110:pos + 110 + namesize - 1].decode()
        pos = (pos + 110 + namesize + 3) & ~3
        if name == "TRAILER!!!":
            return files
        files[name.removeprefix("./")] = data[pos:pos + size]
        pos = (pos + size + 3) & ~3
    raise AssertionError("Missing archive trailer")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("name", choices=[f"native{i}" for i in range(1, 10)], default="native2", nargs="?")
    name = parser.parse_args().name
    dtb_path = OUT / f"{name}.dtb"
    dtb = dtb_path.read_bytes()
    with tempfile.TemporaryDirectory(prefix="native1-unpack-") as temp:
        subprocess.run(["unpack_bootimg", "--boot_img", str(OUT / f"boot-{name}.img"),
                        "--out", temp], check=True)
        unpacked = Path(temp)
        image = (unpacked / "kernel").read_bytes()
        assert (unpacked / "dtb").read_bytes() == dtb
        assert image == (SRC / "arch/arm64/boot/Image").read_bytes()
    assert image.count(dtb) == 1, "Embedded DTB differs from packaged DTB"
    assert (OUT / f"boot-{name}.img").stat().st_size == 100663296
    assert f"-sm8150-codex-{name}-".encode() in image
    config = (OUT / f"{name}.config").read_text()
    for option in ("CONFIG_DRM_PANEL_SAMSUNG_ONEPLUS_DSC=y", "CONFIG_SECURITY_LANDLOCK=y"):
        assert option in config, option
    assert 'CONFIG_LSM="landlock,' in config
    args = fdt(dtb_path, "-ts", "/chosen", "bootargs")
    assert "bringup_usb.dpu=1" in args and "drm_kms_helper.fbdev_emulation=0" in args
    assert len(args) < 511
    for node in ("display-subsystem@ae00000", "display-subsystem@ae00000/dsi@ae94000",
                 "display-subsystem@ae00000/phy@ae94400"):
        assert fdt(dtb_path, "-ts", "/soc@0/" + node, "status") == "disabled"
    panel = "/soc@0/display-subsystem@ae00000/dsi@ae94000/panel@0"
    panel_endpoint = panel + "/port/endpoint"
    output_endpoint = fdt(dtb_path, "-ts", "/__symbols__", "mdss_dsi0_out")
    assert fdt(dtb_path, "-ts", panel, "compatible") == "samsung,oneplus-dsc"
    for endpoint, remote in ((panel_endpoint, output_endpoint), (output_endpoint, panel_endpoint)):
        assert fdt(dtb_path, "-tx", endpoint, "remote-endpoint") == fdt(dtb_path, "-tx", remote, "phandle"), "Incomplete DSI panel graph"
    for path in ("/cpus", fdt(BASE, "-ts", "/__symbols__", "usb_1")):
        assert subtree(BASE, path) == subtree(dtb_path, path), f"Changed recovery-critical tree: {path}"
    archive = (SRC / "usr/initramfs_inc_data").read_bytes()
    assert image.count(archive) == 1, "Embedded initramfs differs from build input"
    files = newc_files(gzip.decompress(archive))
    assert files["init"] == (ROOT / "scripts/initramfs/init-native").read_bytes()
    assert files["hypr/start-usb-services.sh"] == (ROOT / "scripts/initramfs/start-usb-services.sh").read_bytes()
    for script in ("run-hypr-native.sh", "start-native-desktop.sh"):
        assert files[f"hypr/{script}"] == (ROOT / "scripts/initramfs" / script).read_bytes()
    for module in ("evdev", "s6sy761", "touch_overlay"):
        path = OUT / "touch" / f"{module}.ko"
        assert files[f"hypr/touch/{module}.ko"] == path.read_bytes()
        version = subprocess.check_output(["modinfo", "-F", "vermagic", str(path)], text=True)
        assert f"-sm8150-codex-{name}-" in version
    if name in ("native3", "native4", "native5"):
        path = OUT / "power/power_support.ko"
        assert files["hypr/power/power_support.ko"] == path.read_bytes()
        assert files["hypr/start-power.sh"] == (ROOT / "scripts/initramfs/start-power.sh").read_bytes()
        version = subprocess.check_output(["modinfo", "-F", "vermagic", str(path)], text=True)
        assert f"-sm8150-codex-{name}-" in version
        for option in ("CONFIG_CHARGER_QCOM_SMB2=y", "CONFIG_BATTERY_BQ27XXX=y",
                       "CONFIG_BATTERY_BQ27XXX_I2C=y", "CONFIG_INPUT_PM8941_PWRKEY=y"):
            assert option in config, option
        assert (SRC / "drivers/power/supply/qcom_smbx_mobile.h").read_bytes() == (
            ROOT / "kernel/power/qcom_smbx_mobile.h").read_bytes()
        merged = OUT / "power/power-support-test.dtb"
        def symbol(label):
            return fdt(merged, "-ts", "/__symbols__", label)
        for label in ("gpi_dma1", "qupv3_id_1", "i2c8", "pon", "pon_pwrkey", "pm8150b_charger", "spmi_bus"):
            assert fdt(merged, "-ts", symbol(label), "status") == "okay", label
        for label in ("pm8150b_fg", "pm8150b_vbus", "pm8150b_typec", "pon_resin"):
            assert fdt(merged, "-ts", symbol(label), "status") == "disabled", label
        assert fdt(dtb_path, "-ts", symbol("spmi_bus"), "status") == "disabled"
        charger = symbol("pm8150b_charger")
        for prop, label in (("monitored-battery", "mobile_battery"), ("qcom,external-fuel-gauge", "mobile_gauge")):
            assert fdt(merged, "-tx", charger, prop) == fdt(merged, "-tx", symbol(label), "phandle")
        battery = symbol("mobile_battery")
        for prop, value in (("constant-charge-current-max-microamp", 500000),
                            ("constant-charge-voltage-max-microvolt", 4200000),
                            ("voltage-max-design-microvolt", 4200000)):
            assert int(fdt(merged, "-tu", battery, prop)) == value
        assert fdt(merged, "-ts", symbol("mobile_gauge"), "compatible") == "ti,bq27541"
        for path in ("/cpus", symbol("usb_1")):
            assert subtree(dtb_path, path) == subtree(merged, path), path
        print("PASS: delayed power module, external gauge linkage, conservative battery profile,")
        print("      charger/gauge/key drivers built in, matching module and unchanged CPU/USB")
        if name == "native5":
            assert 'CONFIG_RTC_DRV_PM8XXX=y' in config
            assert 'CONFIG_PM_DEBUG=y' in config
            rtc = symbol('pm8150_rtc')
            assert fdt(merged, '-ts', rtc, 'status') == 'okay'
            props = fdt(merged, '-p', rtc).splitlines()
            assert not {'allow-set-time', 'nvmem-cells', 'qcom,uefi-rtc-info'} & set(props)
            assert b'rtc_parent' not in files.get('hypr/start-power.sh', b'')
            print('PASS: RTC enabled before PMIC population; no vendor counter/offset writes; PM diagnostics enabled')
    if name in ("native4", "native5"):
        for node, address, size in (("rmtfs-lower-guard@f2900000", 0xf2900000, 0x1000),
                                    ("rmtfs-upper-guard@f2b01000", 0xf2b01000, 0x1000),
                                    ("memory@f2901000", 0xf2901000, 0x200000)):
            node = "/reserved-memory/" + node
            assert fdt(dtb_path, "-tx", node, "reg") == f"0 {address:x} 0 {size:x}"
            assert "no-map" in fdt(dtb_path, "-p", node).splitlines()
        for path in ("/smem", "/soc@0/remoteproc@4080000", "/soc@0/wifi@18800000"):
            assert fdt(dtb_path, "-ts", path, "status") == "disabled", path
        print("PASS: RMTFS guard pages reserved; SMEM/MPSS/Wi-Fi remain disabled for staged testing")
    print("PASS: boot packaging, embedded DTB/initramfs, CPU/USB preservation, delayed display,")
    print("      fbdev suppression, linked-config selection, Landlock and matching touch modules")


if __name__ == "__main__":
    main()
