#!/usr/bin/env python3
"""Build a local Pixel recovery/desktop image; never access the phone."""
import argparse
import hashlib
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent
BUSYBOX_SHA = '999cb969d09093a71716cfc747bb53cdada3f332c05eb5046c56e0f66a4d6d22'
ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--output', type=Path, required=True)
ap.add_argument('--busybox', type=Path, default=ROOT.parent / 'oneplus7pro/.work/codex-native-initramfs/bin/busybox')
ap.add_argument('--seconds', type=int, default=600, help='automatic reboot interval; 0 leaves manual reboot')
ap.add_argument('--jobs', type=int, default=12)
ap.add_argument('--usb-network', action='store_true', help='build v10 ECM+ACM instead of v9 serial-only')
ap.add_argument('--drm', action='store_true', help='build v11 retained-display DRM with USB networking')
ap.add_argument('--acpm', action='store_true', help='build GS201 ACPM query bring-up controls, inactive at boot')
ap.add_argument('--gpu', action='store_true', help='build guarded GPU power-domain bring-up, implies --acpm')
ap.add_argument('--display-timing', action='store_true', help='build v16 display timing diagnostics, implies --gpu')
ap.add_argument('--direct-scanout', action='store_true', help='build v17 native DMA scanout, implies --display-timing')
ap.add_argument('--panel120', action='store_true', help='build v19 guarded 60/120 Hz panel modes and DPMS, implies --direct-scanout')
ap.add_argument('--persistent-root', action='store_true', help='include UFS/input modules and mount an already installed Pixel root; requires --seconds 0')
a = ap.parse_args()
if a.persistent_root:
    if a.seconds != 0:
        ap.error('--persistent-root requires --seconds 0')
    a.panel120 = True
if a.panel120:
    a.direct_scanout = True
if a.direct_scanout:
    a.display_timing = True
if a.display_timing:
    a.gpu = True
if a.gpu:
    a.acpm = True
if a.acpm:
    a.drm = True
if a.drm:
    a.usb_network = True
if not 0 <= a.seconds <= 86400:
    ap.error('--seconds must be 0..86400')
if hashlib.sha256(a.busybox.read_bytes()).hexdigest() != BUSYBOX_SHA:
    ap.error('BusyBox checksum does not match the verified OnePlus reference')
kernel = ROOT / 'mainline/linux'
base = subprocess.check_output(['git', '-C', str(kernel), 'rev-parse', 'HEAD'], text=True).strip()
expected_base = (ROOT / 'kernel/kernel-base.txt').read_text().strip()
if base != expected_base:
    ap.error('Kernel base differs from the saved v9 checkpoint')
for enabled, stem in ((a.acpm, 'acpm'), (a.gpu, 'gpu')):
    if not enabled:
        continue
    overlay = subprocess.check_output(['dtc', '-@', '-I', 'dts', '-O', 'dtb',
                                      str(ROOT / f'mainline/pixel-{stem}-overlay.dts')])
    (kernel / f'arch/arm64/kernel/pixel_{stem}_overlay.h').write_text(
        '/* SPDX-License-Identifier: GPL-2.0-only */\n'
        f'/* Generated from mainline/pixel-{stem}-overlay.dts */\n'
        f'static const unsigned char pixel_{stem}_overlay[] __aligned(8) = {{\n' +
        '\n'.join('\t' + ', '.join(f'0x{byte:02x}' for byte in overlay[i:i+12]) + ','
                  for i in range(0, len(overlay), 12)) + '\n};\n')
out = a.output.resolve()
out.mkdir(parents=True, exist_ok=False)
root = out / 'root'
for d in ('bin', 'etc', 'dev', 'proc', 'sys', 'tmp', 'run', 'root', 'usr'):
    (root / d).mkdir(parents=True, exist_ok=True)
(root / 'tmp').chmod(0o1777)
(root / 'root').chmod(0o700)
shutil.copy2(a.busybox, root / 'bin/busybox')
applets = subprocess.check_output(['qemu-aarch64', str(a.busybox), '--list'], text=True).splitlines()
for name in applets:
    if name != 'busybox': (root / 'bin' / name).symlink_to('busybox')
if a.gpu:
    fwdir = ROOT / 'out/checkpoints/20260925-gpu-v15/firmware'
    firmware = fwdir / 'mali_csffw.bin'
    if hashlib.sha256(firmware.read_bytes()).hexdigest() != 'a27847ea11f8efb3136340c3ba8aab413ae25145eeb4a7f64ff5edd829a2405b':
        ap.error('Pinned architecture 10.8 firmware checksum mismatch')
    target = root / 'lib/firmware/arm/mali/arch10.8'
    target.mkdir(parents=True)
    shutil.copy2(firmware, target / firmware.name)
    shutil.copy2(fwdir / 'LICENCE.mali_csffw', target / 'LICENCE.mali_csffw')
(root / 'sbin').symlink_to('bin')
(root / 'usr/bin').symlink_to('../bin')
(root / 'usr/sbin').symlink_to('../bin')
(root / 'etc/passwd').write_text('root:x:0:0:Root:/root:/bin/sh\n')
(root / 'etc/group').write_text('root:x:0:\n')
(root / 'etc/os-release').write_text('NAME="Pixel Linux bring-up"\nID=pixel-bringup\nPRETTY_NAME="Pixel Linux RAM-only shell"\n')
if a.usb_network:
    shutil.copy2(ROOT / 'mainline/pixel-usb-network.sh', root / 'etc/pixel-usb-network.sh')
if a.persistent_root:
    shutil.copy2(ROOT / 'scripts/pixel-persistent-start.sh', root / 'etc/pixel-persistent-start.sh')
if a.drm:
    font = bytes(int(x, 16) for x in re.findall(r'^\s*(0x[0-9a-fA-F]{2}),',
                 (kernel / 'lib/fonts/font_8x16.c').read_text(), re.M))
    assert len(font) == 4096
    (out / 'font.h').write_text('/* SPDX-License-Identifier: GPL-2.0; Linux VGA font */\n'
                              'static const unsigned char font[4096] = {' +
                              ','.join(str(x) for x in font) + '};\n')
    subprocess.run(['aarch64-linux-gnu-gcc', '-static', '-O2', '-Wall', '-Wextra',
                    '-I/usr/include/libdrm', '-I' + str(out), str(ROOT / 'mainline/pixel-kms-test.c'),
                    '-o', str(root / 'bin/pixel-kms-test')], check=True)
subprocess.run(['aarch64-linux-gnu-gcc', '-static', '-O2', '-Wall', '-Wextra',
                *(['-DPIXEL_USB_NETWORK'] if a.usb_network else []),
                *(['-DPIXEL_PERSISTENT_ROOT'] if a.persistent_root else []),
                str(ROOT / 'mainline/pixel-shell-init.c'), '-o', str(root / 'ourinit')], check=True)
shutil.copy2(kernel / '.config', out / 'config-before')
shutil.copy2(ROOT / 'kernel/native-bringup-v9.config', kernel / '.config')
subprocess.run([str(kernel / 'scripts/config'), '--file', str(kernel / '.config'),
                '--set-str', 'INITRAMFS_SOURCE', str(root),
                '--set-str', 'BOOT_CONFIG_EMBED_FILE', str(ROOT / 'mainline/bootconfig'),
                '--set-str', 'LOCALVERSION', '-pixel-panel19' if a.panel120 else '-pixel-scanout17' if a.direct_scanout else ('-pixel-display16' if a.display_timing else ('-pixel-gpu15' if a.gpu else ('-pixel-power14' if a.acpm else ('-pixel-drm11' if a.drm else ('-pixel-net10' if a.usb_network else '-pixel-shell9'))))),
                *(['--enable', 'EXYNOS_ACPM_PROTOCOL', '--enable', 'EXYNOS_MBOX',
                   '--enable', 'EXYNOS_ACPM_CLK', '--enable', 'GS201_ACPM_THERMAL',
                   '--disable', 'CPU_FREQ_DEFAULT_GOV_SCHEDUTIL', '--enable', 'CPU_FREQ_DEFAULT_GOV_USERSPACE',
                   '--enable', 'THERMAL_EMULATION', '--set-val', 'THERMAL_EMERGENCY_POWEROFF_DELAY_MS', '3000'] if a.acpm else []),
                *(['--enable', 'GS201_G3D_PM_DOMAINS', '--enable', 'DRM_PANTHOR'] if a.gpu else []),
                *(['--enable', 'DRM_PIXEL_HANDOFF_TIMING'] if a.display_timing else []),
                *(['--enable', 'DRM_PIXEL_SCANOUT'] if a.direct_scanout else []),
                *(['--enable', 'DRM', '--enable', 'DRM_PIXEL_HANDOFF',
                   '--disable', 'DRM_FBDEV_EMULATION', '--disable', 'DRM_PANIC'] if a.drm else []),
                *(['--disable', 'USB_G_SERIAL', '--enable', 'USB_CDC_COMPOSITE'] if a.usb_network else [])], check=True)
with (out / 'build.log').open('w') as log:
    for target in ('olddefconfig', 'Image'):
        subprocess.run(['make', '-C', str(kernel), 'ARCH=arm64',
                        'CROSS_COMPILE=aarch64-linux-gnu-', f'-j{a.jobs}', target],
                       stdout=log, stderr=subprocess.STDOUT, check=True)
    if a.persistent_root:
        modules = out / 'modules'
        modules.mkdir()
        for name, source in (
            ('pixel-ufs.c', ROOT / 'kernel/storage/pixel-ufs.c'),
            ('pixel-powerkey.c', ROOT / 'kernel/powerkey/pixel-powerkey.c'),
            ('pixel_touch_input.c', ROOT / 'mainline/pixel-touch-input.c'),
        ):
            shutil.copy2(source, modules / name)
        (modules / 'Makefile').write_text('obj-m += pixel-ufs.o pixel-powerkey.o pixel_touch_input.o\n')
        old_symbols = {line.split()[1] for line in (kernel / 'Module.symvers').read_text().splitlines()}
        extra = ''.join(line for line in (kernel / 'vmlinux.symvers').read_text().splitlines(True)
                        if line.split()[1] not in old_symbols)
        (modules / 'extra.symvers').write_text(extra)
        subprocess.run(['make', '-C', str(kernel), 'ARCH=arm64',
                        'CROSS_COMPILE=aarch64-linux-gnu-', f'M={modules}',
                        f'KBUILD_EXTRA_SYMBOLS={modules}/extra.symvers', 'modules'],
                       stdout=log, stderr=subprocess.STDOUT, check=True)
        target = root / 'lib/modules/pixel'
        target.mkdir(parents=True)
        for module in modules.glob('*.ko'):
            shutil.copy2(module, target / module.name)
        subprocess.run(['make', '-C', str(kernel), 'ARCH=arm64',
                        'CROSS_COMPILE=aarch64-linux-gnu-', f'-j{a.jobs}', 'Image'],
                       stdout=log, stderr=subprocess.STDOUT, check=True)
shutil.copy2(kernel / 'arch/arm64/boot/Image', out / 'Image')
shutil.copy2(kernel / '.config', out / 'kernel.config')
shutil.copy2(ROOT / 'mainline/pixel-shell-init.c', out / 'pixel-shell-init.c')
shutil.copy2(ROOT / 'mainline/bootconfig', out / 'bootconfig')
for name in ('pixel_earlycon.c', 'pixel_usb.c', 'pixel_watchdog.c'):
    shutil.copy2(kernel / 'arch/arm64/kernel' / name, out / name)
if a.drm:
    shutil.copy2(kernel / 'drivers/gpu/drm/sysfb/pixel_handoff.c', out / 'pixel_handoff.c')
    shutil.copy2(kernel / 'include/linux/pixel_handoff.h', out / 'pixel_handoff.h')
    shutil.copy2(ROOT / 'mainline/pixel-kms-test.c', out / 'pixel-kms-test.c')
if a.direct_scanout:
    shutil.copy2(kernel / 'drivers/gpu/drm/sysfb/pixel_scanout.c', out / 'pixel_scanout.c')
    shutil.copy2(kernel / 'drivers/gpu/drm/sysfb/pixel_panel.h', out / 'pixel_panel.h')
    shutil.copy2(kernel / 'drivers/gpu/drm/sysfb/pixel_bandwidth.h', out / 'pixel_bandwidth.h')
if a.acpm:
    for relative in ('arch/arm64/kernel/pixel_acpm.c',
                     'arch/arm64/kernel/pixel_acpm_overlay.h',
                     'drivers/clk/samsung/clk-gs201.c',
                     'drivers/thermal/samsung/gs201_acpm_thermal.c',
                     'include/dt-bindings/clock/google,gs201.h'):
        shutil.copy2(kernel / relative, out / Path(relative).name)
    shutil.copy2(ROOT / 'mainline/pixel-acpm-overlay.dts', out / 'pixel-acpm-overlay.dts')
if a.gpu:
    for relative in ('arch/arm64/kernel/pixel_gpu.c', 'arch/arm64/kernel/pixel_gpu_overlay.h',
                     'drivers/pmdomain/samsung/gs201-g3d-pd.c'):
        shutil.copy2(kernel / relative, out / Path(relative).name)
    shutil.copy2(ROOT / 'mainline/pixel-gpu-overlay.dts', out / 'pixel-gpu-overlay.dts')
(out / 'kernel-tracked.patch').write_bytes(subprocess.check_output(['git', '-C', str(kernel), 'diff']))
(out / 'kernel-base.txt').write_bytes(subprocess.check_output(['git', '-C', str(kernel), 'rev-parse', 'HEAD']))
cmdline = ('keep_bootcon loglevel=7 printk.time=1 fw_devlink=off clk_ignore_unused '
           'pd_ignore_unused panic=45 rdinit=/ourinit pixel_usb=1 '
           f'pixel_test_seconds={a.seconds}')
if a.usb_network:
    cmdline += ' g_cdc.dev_addr=02:70:07:00:00:01 g_cdc.host_addr=02:70:07:00:00:02'
if a.drm:
    cmdline += ' pixel_drm=1'
if a.direct_scanout:
    cmdline += ' cma=128M@0-4G'
if a.panel120:
    cmdline += ' pixel_scanout.panel120=1'
(out / 'cmdline.txt').write_text(cmdline + '\n')
subprocess.run(['python', str(ROOT / 'scripts/pack-pixel-ram-boot.py'), '--kernel', str(out / 'Image'),
                '--output', str(out / 'boot-pixel-shell.img'), '--cmdline', cmdline], check=True)
with (out / 'SHA256SUMS').open('w') as sums:
    files = sorted(p for p in out.rglob('*') if p.is_file() and not p.is_symlink() and p.name != 'SHA256SUMS')
    for p in files:
        sums.write(hashlib.sha256(p.read_bytes()).hexdigest() + '  ' + str(p.relative_to(out)) + '\n')
print(f'Built {out}/boot-pixel-shell.img; no device commands issued.')
