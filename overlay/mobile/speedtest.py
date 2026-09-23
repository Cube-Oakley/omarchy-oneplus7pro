#!/usr/bin/env python3
"""HTTP throughput test. Prints one JSON object per line for the UI.

Uses Cloudflare's public speed endpoints. Results are application-layer
throughput, not ICMP ping or an ISP marketing number.
"""
import json
import ssl
import sys
import time
import urllib.error
import urllib.request

DOWN = 'https://speed.cloudflare.com/__down?bytes={}'
UP = 'https://speed.cloudflare.com/__up'
UA = 'omarchy-mobile-speedtest/1'
CHUNK = 64 * 1024
PING_BYTES = 1000
DOWN_BYTES = 25 * 1024 * 1024
UP_CHUNK = 256 * 1024
UP_LIMIT = 8 * 1024 * 1024
PHASE_SECONDS = 10


def emit(payload):
    print(json.dumps(payload), flush=True)


def opener():
    context = ssl.create_default_context()
    return urllib.request.build_opener(urllib.request.HTTPSHandler(context=context))


def request(handle, url, data=None, timeout=20):
    req = urllib.request.Request(url, data=data, method='POST' if data is not None else 'GET')
    req.add_header('User-Agent', UA)
    if data is not None:
        req.add_header('Content-Type', 'application/octet-stream')
    return handle.open(req, timeout=timeout)


def mbps(nbytes, seconds):
    if seconds <= 0:
        return 0.0
    return round((nbytes * 8) / seconds / 1_000_000, 1)


def ping(handle, rounds=5):
    samples = []
    for _ in range(rounds):
        start = time.monotonic()
        with request(handle, DOWN.format(PING_BYTES), timeout=8) as response:
            response.read()
        samples.append((time.monotonic() - start) * 1000)
    samples.sort()
    return round(samples[len(samples) // 2], 1)


def download(handle):
    start = time.monotonic()
    total = 0
    with request(handle, DOWN.format(DOWN_BYTES), timeout=PHASE_SECONDS + 5) as response:
        while True:
            elapsed = time.monotonic() - start
            if elapsed >= PHASE_SECONDS:
                break
            block = response.read(CHUNK)
            if not block:
                break
            total += len(block)
            emit({'phase': 'download', 'mbps': mbps(total, elapsed), 'bytes': total})
    return mbps(total, time.monotonic() - start)


def upload(handle):
    start = time.monotonic()
    sent = 0
    blob = b'\0' * UP_CHUNK
    while sent < UP_LIMIT and time.monotonic() - start < PHASE_SECONDS:
        with request(handle, UP, data=blob, timeout=8) as response:
            response.read()
        sent += len(blob)
        emit({'phase': 'upload', 'mbps': mbps(sent, time.monotonic() - start), 'bytes': sent})
    return mbps(sent, time.monotonic() - start)


def run(handle=None):
    emit({'phase': 'start', 'server': 'Cloudflare'})
    http = handle or opener()
    try:
        emit({'phase': 'ping'})
        latency = ping(http)
        emit({'phase': 'ping', 'ms': latency})
        down = download(http)
        emit({'phase': 'download', 'mbps': down, 'done': True})
        up = upload(http)
        emit({'phase': 'upload', 'mbps': up, 'done': True})
        emit({'phase': 'done', 'ping_ms': latency, 'download_mbps': down, 'upload_mbps': up, 'server': 'Cloudflare'})
        return 0
    except (urllib.error.URLError, TimeoutError, OSError, ValueError):
        emit({'phase': 'error', 'error': 'Speed test failed. Check the connection and try again.'})
        return 1


if __name__ == '__main__':
    try:
        sys.exit(run())
    except KeyboardInterrupt:
        emit({'phase': 'error', 'error': 'Speed test cancelled'})
        sys.exit(1)
