#!/usr/bin/env python3
"""Opt-in, manually located Open-Meteo weather with a 15-minute cache."""
import json
import os
from pathlib import Path
import sys
import time
import urllib.parse
import urllib.request

CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config'))) / 'omarchy-mobile/weather.json'
CACHE = Path(os.environ.get('XDG_CACHE_HOME', str(Path.home() / '.cache'))) / 'omarchy-mobile/weather.json'


def get(url, params):
    with urllib.request.urlopen(url + '?' + urllib.parse.urlencode(params), timeout=12) as response:
        return json.load(response)


def read(path):
    try: return json.loads(path.read_text())
    except (OSError, ValueError): return {}


def save(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix('.tmp')
    temp.write_text(json.dumps(data)); temp.replace(path)


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else 'status'
    if command == 'search':
        query = json.load(sys.stdin).get('query', '').strip()
        if len(query) < 2: return {'locations': [], 'error': 'Enter a city or postal code'}
        data = get('https://geocoding-api.open-meteo.com/v1/search', {'name': query, 'count': 5, 'language': 'en'})
        return {'locations': [{'name': ', '.join(filter(None, [r['name'], r.get('admin1'), r.get('country')])),
                               'latitude': r['latitude'], 'longitude': r['longitude']}
                              for r in data.get('results', [])]}
    if command == 'set':
        location = json.load(sys.stdin)
        lat, lon = float(location['latitude']), float(location['longitude'])
        if not -90 <= lat <= 90 or not -180 <= lon <= 180: raise ValueError('Invalid location')
        save(CONFIG, {'name': str(location['name'])[:180], 'latitude': lat, 'longitude': lon})
    config = read(CONFIG)
    if not config: return {'configured': False}
    cached = read(CACHE)
    matches = cached.get('location') == config
    if matches and time.time() - cached.get('fetched', 0) < 900: return cached
    try:
        data = get('https://api.open-meteo.com/v1/forecast', {
            'latitude': config['latitude'], 'longitude': config['longitude'],
            'current': 'temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m',
            'daily': 'temperature_2m_max,temperature_2m_min,weather_code',
            'forecast_days': 3, 'timezone': 'auto', 'temperature_unit': 'fahrenheit', 'wind_speed_unit': 'mph'})
        result = {'configured': True, 'available': True, 'location': config, 'fetched': time.time(),
                  'current': data['current'], 'daily': data['daily']}
        save(CACHE, result)
        return result
    except Exception:
        if matches: return dict(cached, stale=True, error='Offline · showing the last update')
        return {'configured': True, 'available': False, 'location': config, 'error': 'Weather unavailable; try again later'}


if __name__ == '__main__':
    try: result = main()
    except Exception: result = {'error': 'Weather request failed. Check the location and connection.'}
    print(json.dumps(result))
