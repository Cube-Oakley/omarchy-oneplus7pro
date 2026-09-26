#!/usr/bin/env python3
"""Temporary USB-only cache of official Arch Linux ARM repositories.

No host routing, firewall, DNS, package database or system configuration changes.
Run on the development host while the Pixel has its private USB link. Stop with
Ctrl-C after provisioning. Package signatures are still checked on the phone.
"""
import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import re
import shutil
import tempfile
import threading
import urllib.error
import urllib.request

ap = argparse.ArgumentParser(description=__doc__)
ap.add_argument('--cache', type=Path, required=True)
a = ap.parse_args()
cache = a.cache.resolve()
cache.mkdir(parents=True, exist_ok=True)
upstream = 'https://ca.us.mirror.archlinuxarm.org'
lock = threading.Lock()

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        # Host address is used when reached via a loopback-only reverse SSH tunnel.
        if self.client_address[0] not in ('10.77.7.1', '10.77.7.2'):
            self.send_error(403)
            return
        if not re.fullmatch(r'/aarch64/(core|extra|alarm|aur)/[A-Za-z0-9+_.:@%-]+', self.path):
            self.send_error(404)
            return
        # No percent-encoded paths or parent components accepted.
        if '%' in self.path or '..' in self.path:
            self.send_error(404)
            return
        dest = cache / self.path.lstrip('/')
        dest.parent.mkdir(parents=True, exist_ok=True)
        tmp = None
        try:
            if not dest.exists():
                with urllib.request.urlopen(upstream + self.path, timeout=30) as response:
                    with tempfile.NamedTemporaryFile(dir=dest.parent, delete=False) as f:
                        tmp = Path(f.name)
                        shutil.copyfileobj(response, f, 1024 * 1024)
                tmp.replace(dest)
                with dest.open('rb') as f:
                    sha = hashlib.file_digest(f, 'sha256').hexdigest()
                entry = {'url': upstream + self.path, 'path': str(dest.relative_to(cache)),
                         'sha256': sha, 'bytes': dest.stat().st_size}
                with lock, (cache / 'downloads.jsonl').open('a') as log:
                    log.write(json.dumps(entry) + '\n')
            self.send_response(200)
            self.send_header('Content-Length', str(dest.stat().st_size))
            self.end_headers()
            with dest.open('rb') as f:
                shutil.copyfileobj(f, self.wfile, 1024 * 1024)
        except urllib.error.HTTPError as e:
            self.send_error(e.code)
        except (OSError, urllib.error.URLError) as e:
            self.log_error('%s', e)
            try:
                self.send_error(502)
            except OSError:
                pass
        finally:
            if tmp and tmp.exists():
                tmp.unlink()

print(f'USB package cache at http://10.77.7.2:8000; upstream={upstream}', flush=True)
try:
    ThreadingHTTPServer(('10.77.7.2', 8000), Handler).serve_forever()
except KeyboardInterrupt:
    pass
