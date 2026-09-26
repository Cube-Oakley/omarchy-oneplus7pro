#!/usr/bin/env python3
"""Check the diagnostic image against the frozen native5 recovery image."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / '.work/linux-sm8150-dsi-phy-pm'
TEST = ROOT / '.work/linux-sm8150-mmcx-sleep'
OUT = ROOT / 'out/mmcx-sleep-test'
FROZEN = ROOT / 'out/checkpoints/20260917-dsi-phy-pm-test'


def main():
    with tempfile.TemporaryDirectory(prefix='mmcx-image-check-') as tmp:
        paths = [Path(tmp) / 'original', Path(tmp) / 'diagnostic']
        headers = []
        for directory, image in zip(paths, [FROZEN / 'boot.img', OUT / 'boot.img']):
            directory.mkdir()
            headers.append(subprocess.check_output([
                'unpack_bootimg', '--boot_img', str(image), '--out', str(directory)
            ], text=True))
            assert image.stat().st_size == 100663296
        assert headers[0] == headers[1], 'Boot header changed'
        for name in ('dtb', 'ramdisk'):
            assert (paths[0] / name).read_bytes() == (paths[1] / name).read_bytes(), name
        for name in ('.config', 'vmlinux.symvers', 'include/generated/utsrelease.h',
                     'bringup.cpio', 'usr/initramfs_inc_data', 'bringup-guacamole.dtb',
                     'drivers/gpu/drm/msm/dsi/phy/dsi_phy.c',
                     'drivers/gpu/drm/msm/dsi/phy/dsi_phy.h',
                     'drivers/pmdomain/qcom/rpmhpd-cx-sleep-test.h'):
            assert (BASE / name).read_bytes() == (TEST / name).read_bytes(), name
        for directory, tree in zip(paths, [BASE, TEST]):
            image = (directory / 'kernel').read_bytes()
            assert image == (tree / 'arch/arm64/boot/Image').read_bytes()
            # INITRAMFS_COMPRESSION_GZIP: verify the actual compressed payload.
            for name in ('usr/initramfs_inc_data', 'bringup-guacamole.dtb'):
                assert image.count((tree / name).read_bytes()) == 1, name
        assert b'guacamole_cx_sleep_release' in (paths[1] / 'kernel').read_bytes()
        assert b'guacamole_cx_sleep_release' in (paths[0] / 'kernel').read_bytes()
        assert b'guacamole_mmcx_sleep_release' in (paths[1] / 'kernel').read_bytes()
        assert b'guacamole_mmcx_sleep_release' not in (paths[0] / 'kernel').read_bytes()
        assert b'guacamole_mss_handoff_release' not in (paths[1] / 'kernel').read_bytes()
    print('PASS: frozen rollback kernel and diagnostic kernel match build inputs')
    print('PASS: boot header, DTB, ramdisk, embedded initramfs and config unchanged')
    print('PASS: module release and exported symbol table unchanged; CX control and DSI PHY fix unchanged')
    print('Runtime boot and isolated MMCX suspend verification remain pending')


if __name__ == '__main__':
    main()
