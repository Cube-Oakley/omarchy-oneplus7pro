#!/usr/bin/env python3
"""One unplugged RTC-backed suspend with read-only SoC/CPU residency snapshots."""
import argparse
from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import subprocess
import time

ONLINE = Path('/sys/class/power_supply/pm8150b-charger/online')
RUNTIME = Path('/run/user/0')
STATS = Path('/sys/kernel/debug/qcom_stats')
MSS_RELEASE = Path('/sys/kernel/debug/guacamole_mss_handoff_release')
CX_RELEASE = Path('/sys/kernel/debug/guacamole_cx_sleep_release')
MMCX_RELEASE = Path('/sys/kernel/debug/guacamole_mmcx_sleep_release')
VOTE_CACHE = Path('/sys/kernel/debug/guacamole_rpmh_votes/cache')
CLOCK_REFS = Path('/sys/kernel/debug/guacamole_clock_refs')
# Confirmed against this phone's command DB; corner indices, not voltages.
STARTUP_VOTES = {0x30000: (7, 7), 0x30010: (7, 7),
                 0x30060: (0xffffffff, 9), 0x30080: (6, 6), 0x30090: (3, 3)}


def check_cx_votes(released=False, released_address=0x30000):
    data = VOTE_CACHE.read_text()
    if 'truncated=0' not in data.splitlines()[0]:
        raise RuntimeError('RPMh cache snapshot is incomplete')
    votes = {}
    for line in data.splitlines():
        if line.startswith('cache '):
            _, address, sleep, wake = line.split()
            address = int(address, 16)
            if address in votes:
                raise RuntimeError('Duplicate RPMh cache address')
            votes[address] = (int(sleep, 16), int(wake, 16))
    for address, expected in STARTUP_VOTES.items():
        actual = votes.get(address)
        if released and address == released_address:
            valid = actual is not None and 0 <= actual[0] < expected[0] and actual[1] == expected[1]
        else:
            valid = actual == expected
        if not valid:
            raise RuntimeError(f'Unexpected RPMh vote {address:#x}: {actual}')


def check_cx(kernel_version=None):
    # #187 retains the identical CX control and adds the verified DSI PHY fix.
    # Observe both clock and RPMh snapshots when combining those changes.
    allowed = (kernel_version,) if kernel_version else ('#186 ', '#187 ')
    version = os.uname().version
    if not version.startswith(allowed) or CX_RELEASE.read_text().strip() != '0':
        raise RuntimeError(f'Requires kernel {allowed}, CX initially disabled')
    if MSS_RELEASE.exists():
        raise RuntimeError('MSS diagnostic must be absent in the CX test kernel')
    check_power_holds()
    check_cx_votes()
    if version.startswith('#187 '):
        check_clock_inventory()


def check_clock_refs():
    # This is an observation-only trial under the original startup policy.
    # #187 changes DSI PHY clock balancing; its RPMh control is unchanged.
    if os.uname().version.startswith('#188 '):
        check_mmcx()
    else:
        check_cx(kernel_version='#187 ' if '#187 ' in os.uname().version else '#186 ')
    check_clock_inventory()


def check_clock_inventory():
    current = (CLOCK_REFS / 'current').read_text()
    if not current.startswith('missing_provider_clocks=0\n'):
        raise RuntimeError('Clock provider inventory is incomplete')
    if 'current valid=1 ' not in current or ' bi_tcxo prepare=' not in current:
        raise RuntimeError('Clock observer lacks a valid XO sample')
    if not (CLOCK_REFS / 'last_suspend').is_file():
        raise RuntimeError('Clock observer history is missing')


def check_mmcx():
    if not os.uname().version.startswith('#188 '):
        raise RuntimeError('MMCX trial requires kernel #188')
    if MMCX_RELEASE.read_text().strip() != '0' or CX_RELEASE.read_text().strip() != '0':
        raise RuntimeError('MMCX and CX diagnostics must start disabled')
    if MSS_RELEASE.exists():
        raise RuntimeError('MSS diagnostic must be absent')
    check_power_holds()
    check_cx_votes()
    check_clock_inventory()


@contextmanager
def mmcx_trial(enabled):
    if not enabled:
        yield
        return
    check_mmcx()
    try:
        MMCX_RELEASE.write_text('1\n')
        if MMCX_RELEASE.read_text().strip() != '1':
            raise RuntimeError('MMCX diagnostic enable readback failed')
        check_cx_votes(released=True, released_address=0x30080)
        emit('mmcx_sleep_released')
        snapshot('released')
        yield
    finally:
        MMCX_RELEASE.write_text('0\n')
        if MMCX_RELEASE.read_text().strip() != '0':
            raise RuntimeError('MMCX restore failed; reboot to restore startup policy')
        check_cx_votes()
        emit('mmcx_sleep_restored')


@contextmanager
def cx_trial(enabled):
    if not enabled:
        yield
        return
    check_cx()
    try:
        CX_RELEASE.write_text('1\n')
        if CX_RELEASE.read_text().strip() != '1':
            raise RuntimeError('CX diagnostic enable readback failed')
        check_cx_votes(released=True)
        emit('cx_sleep_released')
        snapshot('released')
        yield
    finally:
        # Only changes the SLEEP cache; does not send an ACTIVE RPMh command.
        # A kernel hang still requires recovery; this is not a watchdog.
        CX_RELEASE.write_text('0\n')
        if CX_RELEASE.read_text().strip() != '0':
            raise RuntimeError('CX restore failed; reboot to restore startup policy')
        check_cx_votes()
        emit('cx_sleep_restored')


def check_mss():
    if MSS_RELEASE.read_text().strip() != '0':
        raise RuntimeError('MSS diagnostic must start disabled')
    check_power_holds()


def check_power_holds():
    if Path('/sys/module/camcc_sm8150').exists():
        raise RuntimeError('CAMCC must remain unloaded for the isolated trial')
    controller = Path('/sys/devices/platform/soc@0/18200000.rsc/'
                      '18200000.rsc:power-controller/state_synced')
    if controller.read_text().strip() != '0':
        raise RuntimeError('The original global startup hold must remain active')
    if int(Path('/sys/class/power_supply/bq27541-0/temp').read_text()) >= 390:
        raise RuntimeError('Let the battery cool below 39 C before testing')
    modems = [p for p in Path('/sys/class/remoteproc').glob('remoteproc*')
              if (p / 'name').read_text().strip().lower() in ('modem', 'mpss')]
    if len(modems) != 1 or (modems[0] / 'state').read_text().strip() != 'running':
        raise RuntimeError('Exactly one running MPSS modem is required')


@contextmanager
def mss_trial(enabled):
    if not enabled:
        yield
        return
    check_mss()
    # The finally also runs if enabling, readback, snapshot or suspend fails.
    # A kernel hang/power loss still requires reboot; this is not a watchdog.
    try:
        MSS_RELEASE.write_text('1\n')
        if MSS_RELEASE.read_text().strip() != '1':
            raise RuntimeError('MSS diagnostic enable readback failed')
        emit('mss_released')
        snapshot('released')
        yield
    finally:
        MSS_RELEASE.write_text('0\n')
        if MSS_RELEASE.read_text().strip() != '0':
            raise RuntimeError('MSS restore failed; reboot to restore the startup hold')
        emit('mss_restored')


def emit(event, **values):
    print(json.dumps(dict(event=event, utc=time.time(), **values)), flush=True)


def snapshot(label):
    files = [Path(p) for p in (
        '/proc/sys/kernel/random/boot_id', '/sys/devices/system/cpu/online',
        '/sys/kernel/debug/suspend_stats', '/sys/kernel/debug/wakeup_sources',
        '/sys/kernel/debug/pm_genpd/pm_genpd_summary',
        '/sys/kernel/debug/clk/clk_summary',
        '/sys/class/power_supply/bq27541-0/uevent',
        '/sys/class/power_supply/pm8150b-charger/uevent')]
    # Firmware advertises only 620 SMEM items. The generic driver's APSS file
    # requests item 631 and trips qcom_smem_get's bounds WARN. Only collect the
    # supported SoC records and the modem record known to return useful data.
    files += [STATS / name for name in ('aosd', 'cxsd', 'ddr', 'modem')]
    if MSS_RELEASE.exists():
        files.append(MSS_RELEASE)
    if CX_RELEASE.exists():
        files.append(CX_RELEASE)
    if MMCX_RELEASE.exists():
        files.append(MMCX_RELEASE)
    votes = Path('/sys/kernel/debug/guacamole_rpmh_votes')
    if votes.exists():
        files += list(votes.iterdir())
    if CLOCK_REFS.exists():
        files += list(CLOCK_REFS.iterdir())
    for pattern in ('devices/system/cpu/cpu*/cpuidle/state*/*',
                    'devices/system/cpu/cpu*/cpuidle/state*/s2idle/*',
                    'kernel/debug/pm_genpd/power-domain-cpu*/idle_states'):
        files += [p for p in Path('/sys').glob(pattern) if p.is_file()]
    values = {}
    for path in sorted(files):
        try:
            values[str(path)] = path.read_text().strip()
        except OSError as error:
            values[str(path)] = {'error': str(error)}
    emit(label, boot=time.clock_gettime(time.CLOCK_BOOTTIME),
         mono=time.monotonic(), values=values)


def check():
    if '-sm8150-codex-native5-' not in os.uname().release:
        raise RuntimeError('Requires native5 and its verified resume fixes')
    if not all((STATS / name).is_file() for name in ('aosd', 'cxsd', 'ddr')):
        raise RuntimeError('Load the matching stock qcom_stats module first')
    if ONLINE.read_text().strip() != '1':
        raise RuntimeError('Start while plugged in')
    if Path('/sys/class/rtc/rtc0/wakealarm').read_text().strip():
        raise RuntimeError('An RTC alarm is already armed')
    if int(Path('/sys/class/power_supply/bq27541-0/capacity').read_text()) < 20:
        raise RuntimeError('Charge to at least 20% before testing')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--seconds', type=int, default=90)
    parser.add_argument('--mss-handoff', action='store_true',
                        help='Temporarily release only MSS; requires --seconds 30')
    parser.add_argument('--cx-sleep', action='store_true',
                        help='Temporarily release CX SLEEP only; requires --seconds 30')
    parser.add_argument('--clock-refs', action='store_true',
                        help='Observe clock references without releasing power holds; 30 seconds')
    parser.add_argument('--mmcx-sleep', action='store_true',
                        help='Temporarily release MMCX SLEEP only on #188; 30 seconds')
    args = parser.parse_args()
    if args.mss_handoff:
        parser.error('MSS release trial retired: it caused a modem watchdog and '
                     'blocked RPMh recovery on 2026-09-17; keep control 0')
    if not 30 <= args.seconds <= 300:
        parser.error('--seconds must be 30 to 300')
    if args.cx_sleep and args.seconds != 30:
        parser.error('The CX sleep trial requires --seconds 30')
    if args.mmcx_sleep and (args.seconds != 30 or args.cx_sleep or args.clock_refs):
        parser.error('The MMCX sleep trial requires --seconds 30 and no other trial mode')
    if args.clock_refs and (args.cx_sleep or args.seconds != 30):
        parser.error('The clock observation requires --seconds 30 and no --cx-sleep')
    check()
    if args.cx_sleep:
        check_cx()
    if args.clock_refs:
        check_clock_refs()
    if args.mmcx_sleep:
        check_mmcx()
    if args.check:
        snapshot('preflight')
        return
    os.environ.update(XDG_RUNTIME_DIR=str(RUNTIME), WAYLAND_DISPLAY='wayland-1')
    with open('/run/guacamole-idle-measure.lock', 'w') as trial_lock:
        fcntl.flock(trial_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        emit('armed', expires_in_seconds=600, suspend_seconds=args.seconds)
        deadline = time.monotonic() + 600
        unplugged = None
        while time.monotonic() < deadline:
            if ONLINE.read_text().strip() == '0':
                unplugged = unplugged or time.monotonic()
                if time.monotonic() - unplugged >= 10:
                    break
            else:
                unplugged = None
            time.sleep(1)
        else:
            raise RuntimeError('Expired without unplugging; nothing remains armed')
        with open(RUNTIME / 'omarchy-mobile-power.lock', 'w') as power_lock:
            fcntl.flock(power_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            subprocess.run(['/usr/local/sbin/guacamole-suspend', '--check'], check=True)
            if args.clock_refs:
                check_clock_refs()
            snapshot('before')
            start = (time.clock_gettime(time.CLOCK_BOOTTIME), time.monotonic())
            try:
                with cx_trial(args.cx_sleep), mmcx_trial(args.mmcx_sleep):
                    result = subprocess.run(['/usr/local/sbin/guacamole-suspend',
                                             '--wake-after', str(args.seconds)])
            finally:
                (RUNTIME / 'omarchy-mobile-power.json').write_text(
                    json.dumps({'ignore_until': time.monotonic() + 2}))
            elapsed = time.clock_gettime(time.CLOCK_BOOTTIME) - start[0]
            slept = elapsed - (time.monotonic() - start[1])
            snapshot('after')
            emit('finished', exit_code=result.returncode, suspended_seconds=slept,
                 full_interval=result.returncode == 0 and slept >= args.seconds * .9)
            if result.returncode:
                raise RuntimeError('Suspend command failed; inspect captured diagnostics')


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        emit('aborted', reason=str(error))
        raise SystemExit(1)
