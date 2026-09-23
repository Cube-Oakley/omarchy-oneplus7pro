#!/usr/bin/env python3
"""Portable CPU, memory, thermal and process snapshot from procfs/sysfs.

Process ranking uses CPU time share, not milliwatts. Energy counters are not
assumed to exist.
"""
import json
import os
from pathlib import Path
import time

CACHE = Path(os.environ.get('XDG_CACHE_HOME', str(Path.home() / '.cache'))) / 'omarchy-mobile/stats.json'


def read(path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return {}


def save(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix('.tmp')
    temp.write_text(json.dumps(data))
    temp.replace(path)


def cpu_times(stat_text):
    total = None
    cores = []
    for line in stat_text.splitlines():
        if not line.startswith('cpu'):
            continue
        parts = line.split()
        nums = [int(value) for value in parts[1:]]
        idle = nums[3] + (nums[4] if len(nums) > 4 else 0)
        row = {'name': parts[0], 'total': sum(nums), 'idle': idle}
        if parts[0] == 'cpu':
            total = row
        else:
            cores.append(row)
    return total, cores


def percent(previous, current):
    if not previous or not current:
        return None
    total = current['total'] - previous['total']
    if total <= 0:
        return None
    idle = current['idle'] - previous['idle']
    return round(max(0, min(100, 100.0 * (1 - idle / total))), 1)


def memory(meminfo_text):
    fields = {}
    for line in meminfo_text.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0].endswith(':'):
            try:
                fields[parts[0][:-1]] = int(parts[1])
            except ValueError:
                continue
    total = fields.get('MemTotal')
    available = fields.get('MemAvailable')
    if not total:
        return {'available': False}
    used = total - available if available is not None else None
    return {
        'available': True,
        'total_mb': round(total / 1024, 1),
        'used_mb': round(used / 1024, 1) if used is not None else None,
        'available_mb': round(available / 1024, 1) if available is not None else None,
        'percent': round(100.0 * used / total, 1) if used is not None else None,
    }


def thermals(root):
    zones = []
    if not root.is_dir():
        return zones
    for zone in sorted(root.glob('thermal_zone*')):
        try:
            celsius = int((zone / 'temp').read_text()) / 1000
            name = (zone / 'type').read_text().strip() or zone.name
        except (OSError, ValueError):
            continue
        if not -40 <= celsius <= 150:
            continue
        zones.append({'name': name, 'celsius': round(celsius, 1)})
    zones.sort(key=lambda row: row['celsius'], reverse=True)
    return zones[:10]


def loadavg(text):
    parts = text.split()
    if len(parts) < 3:
        return None
    try:
        return [round(float(parts[0]), 2), round(float(parts[1]), 2), round(float(parts[2]), 2)]
    except ValueError:
        return None


def parse_stat(text):
    left = text.find('(')
    right = text.rfind(')')
    if left < 0 or right < left:
        raise ValueError('stat')
    pid = int(text[:left].strip())
    comm = text[left + 1:right]
    fields = text[right + 1:].split()
    return pid, comm, int(fields[11]), int(fields[12])


def rss_mb(status_text):
    for line in status_text.splitlines():
        if line.startswith('VmRSS:'):
            return round(int(line.split()[1]) / 1024, 1)
    return None


def processes(proc, previous, total_delta, limit=6):
    previous_procs = (previous or {}).get('processes', {})
    rows = []
    for entry in proc.iterdir():
        if not entry.name.isdigit():
            continue
        try:
            cmdline = (entry / 'cmdline').read_bytes()
            if not cmdline:
                continue
            pid, comm, utime, stime = parse_stat((entry / 'stat').read_text())
            rss = rss_mb((entry / 'status').read_text())
        except (OSError, ValueError, IndexError):
            continue
        ticks = utime + stime
        prior = previous_procs.get(str(pid))
        share = None
        if prior is not None and total_delta and total_delta > 0:
            share = round(max(0, 100.0 * (ticks - prior) / total_delta), 1)
        rows.append({'pid': pid, 'name': comm, 'cpu': share, 'rss_mb': rss, 'ticks': ticks})
    ranked = sorted(rows, key=lambda row: (row['cpu'] is not None, row['cpu'] or 0, row['rss_mb'] or 0), reverse=True)
    return ranked[:limit], {str(row['pid']): row['ticks'] for row in rows}


def snapshot(proc=Path('/proc'), thermal=Path('/sys/class/thermal'), previous=None, now=None):
    now = time.time() if now is None else now
    stat_text = (proc / 'stat').read_text()
    total, cores = cpu_times(stat_text)
    mem = memory((proc / 'meminfo').read_text())
    load = loadavg((proc / 'loadavg').read_text()) if (proc / 'loadavg').exists() else None
    prev_cpu = (previous or {}).get('cpu')
    total_delta = (total['total'] - prev_cpu['total']) if total and prev_cpu else None
    procs, proc_ticks = processes(proc, previous, total_delta)
    return {
        'available': True,
        'cpu': percent(prev_cpu, total),
        'cores': [percent(prev, core) for prev, core in zip((previous or {}).get('cores') or [], cores)],
        'core_count': len(cores),
        'memory': mem,
        'load': load,
        'thermals': thermals(thermal),
        'processes': [{'pid': row['pid'], 'name': row['name'], 'cpu': row['cpu'], 'rss_mb': row['rss_mb']} for row in procs],
        'sampled': now,
        '_cpu': total,
        '_cores': cores,
        '_processes': proc_ticks,
    }


def public(result):
    return {key: value for key, value in result.items() if not key.startswith('_')}


def main(proc=Path('/proc'), thermal=Path('/sys/class/thermal'), cache=CACHE):
    previous = read(cache)
    try:
        result = snapshot(proc=proc, thermal=thermal, previous=previous or None)
    except OSError:
        return {'available': False}
    save(cache, {
        'cpu': result['_cpu'],
        'cores': result['_cores'],
        'processes': result['_processes'],
        'sampled': result['sampled'],
    })
    return public(result)


if __name__ == '__main__':
    print(json.dumps(main()))
