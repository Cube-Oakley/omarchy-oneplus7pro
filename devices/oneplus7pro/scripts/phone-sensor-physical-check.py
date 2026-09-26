#!/usr/bin/env python3
"""Guided physical check of the accelerometer's axes and the proximity sensor
(docs/sensors-20260924.md). The phone buzzes at each step:

  twice   get ready (12 s)
  once    hold it upright in portrait, top edge up, screen towards you
  once    landscape, left edge down, screen towards you
  once    lay it flat face up and cover the top of the screen with a hand
  long    done: uncover it

It streams the accelerometer and proximity sensor throughout and prints each
step's mean acceleration and the proximity changes. With --proximity it
instead streams the proximity and light sensors for 22 s (two buzzes to
start, a long one to stop) while the top of the screen is covered and
uncovered, and prints both over time. Needs phone-ssc-census.py installed as
/root/sensors-bringup/bin/ssc_census.py. Run on the phone:
    bash scripts/phone-ssh.sh 'python3 - [--proximity]' < scripts/phone-sensor-physical-check.py

Subscriptions start 1.5 s apart: two new clients subscribing within the same
moment lost one of the two streams.
"""
import socket
import struct
import subprocess
import sys
import threading
import time

sys.path.insert(0, "/root/sensors-bringup/bin")
import ssc_census as ssc  # noqa: E402

ACCEL = "1fbb6afc01727ea69a418d19f8d7ba44"
PROXIMITY = "4895ecea145f6a962a462eac2a9a1477"
LIGHT = "4895ecea145f6a962a462eac2a9a1071"
CONTROLS = "/root/.local/bin/omarchy-mobile-controls"
LEAD_IN, SETTLE, STEP = 12, 3, 8
STEPS = [
    ("portrait, top edge up", STEP),
    ("landscape, left edge down", STEP),
    ("flat, top of the screen covered", STEP),
]


def buzz(ms, times=1):
    for i in range(times):
        subprocess.run([CONTROLS, "vibrate", str(ms), "80"], check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if i + 1 < times:
            time.sleep(0.35)


def collect(suid_hex, msg_id, payload, out, stop):
    """Subscribe to one sensor; append (receive time, event id, fields) until stop."""
    sock = socket.socket(socket.AF_QIPCRTR, socket.SOCK_DGRAM)
    sock.settimeout(0.5)
    node, port = ssc.find_service(sock)
    suid = (int(suid_hex[16:], 16), int(suid_hex[:16], 16))
    sock.sendto(ssc.client_request(1, suid, msg_id, payload), (node, port))
    while not stop.is_set():
        try:
            data, _ = sock.recvfrom(65536)
        except socket.timeout:
            continue
        if len(data) < 7:
            continue
        _txn, qmi_id, tlvs = ssc.tlvs_of(data)
        v = tlvs.get(0x02, b"")
        if qmi_id not in (ssc.IND_SMALL, ssc.IND_LARGE) or len(v) < 2:
            continue
        for event in ssc.parse(v[2:2 + struct.unpack_from("<H", v)[0]]).get(2, []):
            ev = ssc.parse(event) if isinstance(event, bytes) else {}
            out.append((time.monotonic(), ev.get(1, [None])[0], ssc.parse(ev.get(3, [b""])[0])))
    sock.close()


def floats(fields):
    vals = []
    for raw in fields.get(1, []):
        if isinstance(raw, bytes):
            vals += struct.unpack("<%df" % (len(raw) // 4), raw[:len(raw) // 4 * 4])
        else:
            vals.append(struct.unpack("<f", struct.pack("<I", raw & 0xFFFFFFFF))[0])
    return vals


def main():
    accel, prox, stop = [], [], threading.Event()
    threads = [
        threading.Thread(target=collect, args=(ACCEL, ssc.MSG_STD_CONFIG,
                                               ssc.pb(1, 5, struct.pack("<f", 10.0)), accel, stop)),
        threading.Thread(target=collect, args=(PROXIMITY, ssc.MSG_ON_CHANGE_CONFIG, b"", prox, stop)),
    ]
    for t in threads:
        t.start()
        time.sleep(1.5)
    start = time.monotonic()
    buzz(120, 2)
    print("get ready: %d s" % LEAD_IN, flush=True)
    time.sleep(LEAD_IN)
    windows = []
    for name, length in STEPS:
        buzz(250)
        t0 = time.monotonic()
        print("step: %s" % name, flush=True)
        time.sleep(length)
        windows.append((name, t0 + SETTLE, t0 + length))
    buzz(900)
    time.sleep(4)
    stop.set()
    for t in threads:
        t.join()
    print()
    for name, a, b in windows:
        samples = [floats(f) for t, eid, f in accel if eid == 1025 and a <= t <= b]
        samples = [s for s in samples if len(s) >= 3]
        if samples:
            mean = [sum(s[i] for s in samples) / len(samples) for i in range(3)]
            print("%-34s accel mean (%6.2f, %6.2f, %6.2f) m/s^2 over %d samples"
                  % (name, mean[0], mean[1], mean[2], len(samples)))
        else:
            print("%-34s no accel samples" % name)
    print("\nproximity events (seconds from start; state 1 = near, raw ADC):")
    for t, eid, f in prox:
        if eid == 769:
            state = f.get(1, [None])[0]
            print("  %5.1f s  state %s  raw %s" % (t - start, state, f.get(2, [None])[0]))


def proximity_check():
    prox, light, accel, stop = [], [], [], threading.Event()
    threads = [
        threading.Thread(target=collect, args=(PROXIMITY, ssc.MSG_ON_CHANGE_CONFIG, b"", prox, stop)),
        threading.Thread(target=collect, args=(LIGHT, ssc.MSG_STD_CONFIG,
                                               ssc.pb(1, 5, struct.pack("<f", 5.0)), light, stop)),
        # Shows whether the phone was turned face down (z negative).
        threading.Thread(target=collect, args=(ACCEL, ssc.MSG_STD_CONFIG,
                                               ssc.pb(1, 5, struct.pack("<f", 5.0)), accel, stop)),
    ]
    for t in threads:
        t.start()
        time.sleep(1.5)
    start = time.monotonic()
    buzz(120, 2)
    time.sleep(22)
    buzz(900)
    time.sleep(2)
    stop.set()
    for t in threads:
        t.join()
    rows = [(t, "proximity state %s raw %s" % (f.get(1, [None])[0], f.get(2, [None])[0]))
            for t, eid, f in prox if eid == 769]
    last = None
    for t, eid, f in light:
        lux = floats(f)[:1] if eid == 1025 else []
        if lux and (last is None or abs(lux[0] - last) >= max(10, 0.3 * last)):
            rows.append((t, "light %.0f" % lux[0]))
            last = lux[0]
    facing = None
    for t, eid, f in accel:
        z = floats(f)[2:3] if eid == 1025 else []
        if z and abs(z[0]) > 7 and (z[0] > 0) != facing:
            facing = z[0] > 0
            rows.append((t, "phone face %s (z %.1f)" % ("up" if facing else "down", z[0])))
    for t, text in sorted(rows):
        print("%5.1f s  %s" % (t - start, text))
    print("light events %d, proximity events %d"
          % (sum(1 for _, eid, _ in light if eid == 1025), sum(1 for _, eid, _ in prox if eid == 769)))


if __name__ == "__main__":
    proximity_check() if "--proximity" in sys.argv else main()
