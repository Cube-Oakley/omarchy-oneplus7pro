#!/usr/bin/env python3
"""Opt-in, manually located Open-Meteo weather with a 15-minute cache."""
from datetime import date
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


def condition_kind(code):
    try:
        code = int(code)
    except (TypeError, ValueError):
        return 'unknown'
    if code == 0: return 'clear'
    if code <= 2: return 'mostly_clear'
    if code <= 4: return 'cloudy'
    if code <= 48: return 'fog'
    if code <= 57: return 'drizzle'
    if code <= 67: return 'rain'
    if code <= 77: return 'snow'
    if code <= 82: return 'showers'
    if code <= 86: return 'snow'
    return 'thunder'


def condition_name(code):
    kind = condition_kind(code)
    return {
        'clear': 'Clear skies',
        'mostly_clear': 'Partly cloudy',
        'cloudy': 'Cloudy',
        'fog': 'Fog',
        'drizzle': 'Drizzle',
        'rain': 'Rain',
        'snow': 'Snow',
        'showers': 'Showers',
        'thunder': 'Thunderstorms',
        'unknown': 'Weather',
    }[kind]


def forecast_rows(daily, today=None):
    times = daily.get('time') or []
    highs = daily.get('temperature_2m_max') or []
    lows = daily.get('temperature_2m_min') or []
    codes = daily.get('weather_code') or []
    today = date.today() if today is None else today
    rows = []
    for index, stamp in enumerate(times):
        try:
            day = date.fromisoformat(stamp[:10])
        except ValueError:
            continue
        delta = (day - today).days
        weekday = day.strftime('%A')
        if delta == 0: label = 'Today'
        elif delta == 1: label = 'Tomorrow'
        else: label = weekday
        code = codes[index] if index < len(codes) else None
        rows.append({
            'date': day.isoformat(),
            'weekday': weekday,
            'label': label,
            'code': code,
            'kind': condition_kind(code),
            'condition': condition_name(code),
            'min': lows[index] if index < len(lows) else None,
            'max': highs[index] if index < len(highs) else None,
        })
    return rows


def enrich(result, today=None):
    current = result.get('current') or {}
    code = current.get('weather_code')
    result['kind'] = condition_kind(code)
    result['condition'] = condition_name(code)
    result['daily_forecast'] = forecast_rows(result.get('daily') or {}, today=today)
    return result


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
    if matches and time.time() - cached.get('fetched', 0) < 900:
        return enrich(cached)
    try:
        data = get('https://api.open-meteo.com/v1/forecast', {
            'latitude': config['latitude'], 'longitude': config['longitude'],
            'current': 'temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m',
            'daily': 'temperature_2m_max,temperature_2m_min,weather_code',
            'forecast_days': 5, 'timezone': 'auto', 'temperature_unit': 'fahrenheit', 'wind_speed_unit': 'mph'})
        result = {'configured': True, 'available': True, 'location': config, 'fetched': time.time(),
                  'current': data['current'], 'daily': data['daily']}
        save(CACHE, result)
        return enrich(result)
    except Exception:
        if matches: return enrich(dict(cached, stale=True, error='Offline · showing the last update'))
        return {'configured': True, 'available': False, 'location': config, 'error': 'Weather unavailable; try again later'}


if __name__ == '__main__':
    try: result = main()
    except Exception: result = {'error': 'Weather request failed. Check the location and connection.'}
    print(json.dumps(result))
