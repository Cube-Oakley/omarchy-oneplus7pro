#!/usr/bin/env python3
"""Play a short tone on one speaker channel and measure it with a phone mic.

Usage: phone-speaker-loopback.py <left|right|both> <level dBFS> <mic 1|3|4|5>
           [--freq HZ] [--mic-gain ADC:DEC]

Runs on the phone. Suspends the PipeWire speaker sink and microphone source so
ALSA owns both front ends, records from the chosen AMIC input, plays a faded
S16 tone straight to the MultiMedia1 PCM (no route cap), and reports the
tone-frequency component before and during the tone. AMIC5 has no microphone
behind it, so a tone there means electrical coupling, not sound. Left is the
upper amplifier (slot 0, 0x34) and right the lower one (slot 1, 0x35).

Levels are true dBFS only in S16: the ADSP plays S24_LE samples 48 dB low
(docs/speakers-20260922.md), so measurements before that finding that played
S24_LE were 48 dB quieter than their labels.
"""
import math
import os
from pathlib import Path
import struct
import subprocess as sp
import sys
import tempfile
import time
import wave

RATE = 48000
TONE_START, TONE_SECONDS, RECORD_SECONDS = 1.0, 1.5, 3.5
MAX_LEVEL = -12.0
AMPS = ('0034', '0035')
ENV = dict(os.environ, XDG_RUNTIME_DIR='/run/user/0',
           PULSE_SERVER='unix:/run/user/0/pulse/native')


def run(*args):
    return sp.run(args, check=True, capture_output=True, text=True, env=ENV).stdout


def cset(name, value):
    run('amixer', '-q', '-c', 'Pro', 'cset', f'name={name}', str(value))


def suspend_speakers(value):
    """Suspend or resume the speaker sinks: the hardware sink closes the PCM."""
    done = 0
    for sink in ('guacamole-speakers', 'guacamole-speakers-hw'):
        if sp.run(['pactl', 'suspend-sink', sink, value], capture_output=True, env=ENV).returncode == 0:
            done += 1
    if not done:
        raise SystemExit('no speaker sink to suspend')


def frontend(name, direction):
    for line in Path('/proc/asound/pcm').read_text().splitlines():
        if f': {name} ' in line and direction in line:
            return int(line[3:5])
    raise SystemExit(f'no {name} {direction} front end')


def diagnostics():
    return {a: Path(f'/sys/bus/i2c/devices/2-{a}/diagnostics').read_text().split()
            for a in AMPS}


def tone_file(path, channel, level, freq):
    amplitude = 10 ** (level / 20) * 32767
    fade = int(0.025 * RATE)
    total = int(TONE_SECONDS * RATE)
    frames = bytearray()
    for n in range(total):
        envelope = min(1.0, n / fade, (total - 1 - n) / fade)
        sample = int(amplitude * envelope * math.sin(2 * math.pi * freq * n / RATE))
        left = sample if channel in ('left', 'both') else 0
        right = sample if channel in ('right', 'both') else 0
        frames += struct.pack('<hh', left, right)
    path.write_bytes(frames)


def component(samples, freq):
    """Sine amplitude at freq in dBFS, Hann-windowed Goertzel."""
    n = len(samples)
    coeff = 2 * math.cos(2 * math.pi * freq / RATE)
    s1 = s2 = 0.0
    for i, x in enumerate(samples):
        w = 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1))
        s1, s2 = x / 32768 * w + coeff * s1 - s2, s1
    power = s1 * s1 + s2 * s2 - coeff * s1 * s2
    amplitude = 4 * math.sqrt(max(power, 0.0)) / n
    return 20 * math.log10(amplitude) if amplitude > 0 else -150.0


def median(values):
    values = sorted(values)
    return values[len(values) // 2]


def main(argv):
    args = argv[1:]
    freq, mic_gain = 1000.0, (20, 84)
    if '--freq' in args:
        i = args.index('--freq'); freq = float(args[i + 1]); del args[i:i + 2]
    if '--mic-gain' in args:
        i = args.index('--mic-gain'); mic_gain = tuple(map(int, args[i + 1].split(':'))); del args[i:i + 2]
    if len(args) != 3 or args[0] not in ('left', 'right', 'both') or args[2] not in '1345':
        print(__doc__.strip().split('\n\n')[0], file=sys.stderr)
        return 2
    channel, level, mic = args[0], float(args[1]), int(args[2])
    if level > MAX_LEVEL:
        raise SystemExit(f'refusing {level} dBFS; limit is {MAX_LEVEL} dBFS until protection exists')
    play, record = frontend('MultiMedia1', 'playback'), frontend('MultiMedia2', 'capture')
    suspend_speakers('1')
    run('pactl', 'suspend-source', 'guacamole-mic', '1')
    try:
        time.sleep(0.5)
        for f in (f'/proc/asound/card0/pcm{play}p/sub0/status', f'/proc/asound/card0/pcm{record}c/sub0/status'):
            if Path(f).read_text().strip() != 'closed':
                raise SystemExit(f'{f} is busy')
        adc = 'ADC4' if mic in (4, 5) else f'ADC{mic}'
        for a in ('ADC1', 'ADC3', 'ADC4'):
            cset(f'{a} Volume', 0)
        cset('AMIC4_5 SEL', 'AMIC5' if mic == 5 else 'AMIC4')
        cset('AMIC MUX0', adc)
        cset(f'{adc} Volume', mic_gain[0])
        cset('DEC0 Volume', mic_gain[1])
        with tempfile.TemporaryDirectory() as tmp:
            tone, capture = Path(tmp) / 'tone.s16', Path(tmp) / 'capture.wav'
            tone_file(tone, channel, level, freq)
            rec = sp.Popen(['arecord', '-q', '-D', f'hw:Pro,{record}', '-f', 'S16_LE', '-r', str(RATE),
                            '-c', '1', '-d', str(math.ceil(RECORD_SECONDS)), str(capture)])
            time.sleep(TONE_START)
            player = sp.Popen(['aplay', '-q', '-D', f'hw:Pro,{play}', '-t', 'raw', '-f', 'S16_LE',
                               '-r', str(RATE), '-c', '2', str(tone)])
            time.sleep(TONE_SECONDS / 2)
            during = diagnostics()
            if player.wait(timeout=10) or rec.wait(timeout=10):
                raise SystemExit('aplay or arecord failed')
            time.sleep(0.5)
            after = diagnostics()
            with wave.open(str(capture)) as w:
                data = struct.unpack(f'<{w.getnframes()}h', w.readframes(w.getnframes()))
    finally:
        # Restore the supervisor's default capture route and gains.
        for a in ('ADC1', 'ADC3'):
            cset(f'{a} Volume', 0)
        cset('AMIC4_5 SEL', 'AMIC4')
        cset('AMIC MUX0', 'ADC4')
        cset('ADC4 Volume', 12)
        cset('DEC0 Volume', 88)
        run('pactl', 'suspend-source', 'guacamole-mic', '0')
        suspend_speakers('0')
    window = RATE // 10
    # Arecord starts before TONE_START; allow 0.3 s of slack on each side.
    baseline = [component(data[i:i + window], freq)
                for i in range(int(0.2 * RATE), int((TONE_START - 0.3) * RATE), window)]
    tone_windows = [component(data[i:i + window], freq)
                    for i in range(int((TONE_START + 0.4) * RATE),
                                   int((TONE_START + TONE_SECONDS - 0.4) * RATE), window)]
    if os.environ.get('LOOPBACK_TIMELINE'):
        for i in range(0, len(data) - window, window):
            seg = data[i:i + window]
            rms = math.sqrt(sum(x * x for x in seg) / window) / 32768
            print(f'  t={i / RATE:4.1f}s {freq:.0f}Hz={component(seg, freq):6.1f} '
                  f'rms={20 * math.log10(rms) if rms else -150:6.1f} dBFS')
    base, during_level = median(baseline), median(tone_windows)
    # Harmonics show a speaker being driven past its linear range.
    start, end = int((TONE_START + 0.4) * RATE), int((TONE_START + TONE_SECONDS - 0.4) * RATE)
    harmonics = [median([component(data[i:i + window], freq * k) for i in range(start, end, window)])
                 for k in (2, 3)]
    fundamental = 10 ** (during_level / 20)
    thd = math.sqrt(sum((10 ** (h / 20)) ** 2 for h in harmonics)) / fundamental * 100
    peak = max(abs(x) for x in data[start:end]) / 32768
    print(f'{channel} {level:+.0f} dBFS {freq:.0f} Hz -> AMIC{mic} (ADC {mic_gain[0]}, DEC0 {mic_gain[1]}): '
          f'baseline {base:.1f} dBFS, tone {during_level:.1f} dBFS, rise {during_level - base:+.1f} dB, '
          f'H2 {harmonics[0]:.1f} H3 {harmonics[1]:.1f} dBFS, THD {thd:.1f}%, mic peak '
          f'{20 * math.log10(peak) if peak else -150:.1f} dBFS')
    for a in AMPS:
        temp = next((f for f in during[a] if f.startswith('temp=')), 'temp=?')
        print(f'  0x{a[2:]} during: {" ".join(during[a][:5])} {temp}  after: {" ".join(after[a][:5])}')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
