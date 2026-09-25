#!/usr/bin/env python3
"""Shared power-key interaction; hardware policy lives in an optional adapter."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import subprocess
import time


class PowerButton:
    def __init__(self):
        self.runtime = Path(os.environ.get('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}'))
        config = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config')))
        self.adapter = config / 'omarchy-mobile/suspend'
        self.display = str(Path.home() / '.local/bin/omarchy-mobile-display')
        self.prefs = config / 'omarchy-mobile/prefs.json'
        # Present while the always-on display shows (omarchy-mobile-display).
        self.ambient = self.runtime / 'omarchy-mobile-ambient'
        self.state = self.runtime / 'omarchy-mobile-power.json'
        self.log = Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state'))) / 'omarchy-mobile/power-button.log'

    def record(self, action, **details):
        self.log.parent.mkdir(parents=True, exist_ok=True)
        with self.log.open('a') as stream:
            stream.write(json.dumps(dict(time=time.time(), action=action, **details)) + '\n')

    def load(self):
        try:
            return json.loads(self.state.read_text())
        except (OSError, ValueError):
            return {}

    def save(self, state):
        self.state.write_text(json.dumps(state))

    def display_on(self):
        monitors = json.loads(subprocess.check_output(['hyprctl', '-j', 'monitors'], timeout=5))
        if not monitors:
            raise RuntimeError('No compositor monitor available')
        return any(monitor['dpmsStatus'] for monitor in monitors)

    def set_display(self, action):
        subprocess.run([self.display, action], check=True, timeout=15)

    def start_display(self, action):
        return subprocess.Popen([self.display, action])

    def always_on(self):
        try:
            return json.loads(self.prefs.read_text()).get('alwaysOn') is True
        except (OSError, ValueError, AttributeError):
            return False

    def act(self):
        if self.ambient.exists():
            self.set_display('on')
            self.record('ambient-wake')
            return
        if not self.display_on():
            self.set_display('on')
            self.record('display-on')
            return
        # The always-on display keeps the panel lit, so it never suspends.
        if self.always_on():
            self.set_display('ambient')
            self.record('ambient')
            return
        # The close has to start before suspend policy. That check used to run first.
        visual = self.start_display('off')
        if not os.access(self.adapter, os.X_OK):
            visual.wait(timeout=8)
            self.record('display-off', reason='No suspend adapter installed')
            return
        ready = subprocess.run([str(self.adapter), '--check'], capture_output=True, text=True, timeout=10)
        if ready.returncode:
            visual.wait(timeout=8)
            self.record('display-off', reason=(ready.stdout + ready.stderr).strip())
            return
        try:
            visual.wait(timeout=8)
            command = [str(self.adapter)]
            alarm = self.runtime / 'omarchy-mobile-power-test-alarm'
            if alarm.exists():
                seconds = int(alarm.read_text())
                if not 10 <= seconds <= 600:
                    raise RuntimeError('Invalid test wake alarm')
                command += ['--wake-after', str(seconds)]
            self.record('suspend-start', fallback_alarm=alarm.exists())
            result = subprocess.run(command)
            self.record('suspend-return', exit_code=result.returncode)
        finally:
            if visual.poll() is None:
                visual.wait(timeout=8)
            self.save({'ignore_until': time.monotonic() + 2})
            self.set_display('on')

    def event(self, event):
        with (self.runtime / 'omarchy-mobile-power.lock').open('w') as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                return  # Includes key events during suspend/resume.
            state = self.load()
            now = time.monotonic()
            if now < state.get('ignore_until', 0):
                self.record('ignored-resume-event', event=event)
                return
            if event == 'press':
                self.save({'pressed': now})
                return
            self.save({})
            if 'pressed' not in state or not 0 <= now - state['pressed'] < 60:
                self.record('ignored-unpaired-release')
                return
            self.act()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('event', choices=('press', 'release'))
    args = parser.parse_args()
    button = PowerButton()
    try:
        button.event(args.event)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        button.record('error', detail=str(error))
        # Errors should leave a usable screen, never silently reattempt sleep.
        button.set_display('on')
        raise SystemExit(str(error))


if __name__ == '__main__':
    main()
