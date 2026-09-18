#!/usr/bin/env python3
"""Read a system battery through Linux's standard power_supply interface."""
import json
from pathlib import Path


def read_battery(root=Path('/sys/class/power_supply')):
    for supply in sorted(root.glob('*')):
        try:
            fields = dict(line.split('=', 1) for line in (supply / 'uevent').read_text().splitlines() if '=' in line)
        except OSError:
            continue
        if (fields.get('POWER_SUPPLY_TYPE') != 'Battery'
                or fields.get('POWER_SUPPLY_SCOPE') == 'Device'
                or fields.get('POWER_SUPPLY_PRESENT', '1') != '1'):
            continue
        try:
            capacity = int(fields['POWER_SUPPLY_CAPACITY'])
        except (KeyError, ValueError):
            continue
        if not 0 <= capacity <= 100:
            continue
        status = fields.get('POWER_SUPPLY_STATUS', 'Unknown')
        result = {'available': True, 'name': supply.name, 'capacity': capacity,
                  'status': status, 'charging': status == 'Charging'}
        for key, field, scale in (
                ('current_ma', 'CURRENT_NOW', 1000), ('voltage_v', 'VOLTAGE_NOW', 1000000),
                ('temperature_c', 'TEMP', 10), ('charge_mah', 'CHARGE_NOW', 1000),
                ('full_mah', 'CHARGE_FULL', 1000), ('design_mah', 'CHARGE_FULL_DESIGN', 1000),
                ('energy_wh', 'ENERGY_NOW', 1000000)):
            try: result[key] = int(fields['POWER_SUPPLY_' + field]) / scale
            except (KeyError, ValueError): result[key] = None
        result['health'] = fields.get('POWER_SUPPLY_HEALTH', 'Unknown')
        result['chargers'] = []
        for other in sorted(root.glob('*')):
            try:
                data = dict(line.split('=', 1) for line in (other / 'uevent').read_text().splitlines() if '=' in line)
                if data.get('POWER_SUPPLY_ONLINE') != '1' or data.get('POWER_SUPPLY_TYPE') == 'Battery': continue
                result['chargers'].append({'name': other.name,
                    'status': data.get('POWER_SUPPLY_STATUS', 'Unknown'),
                    'type': data.get('POWER_SUPPLY_USB_TYPE', data.get('POWER_SUPPLY_TYPE', '')),
                    'input_limit_ma': int(data['POWER_SUPPLY_CURRENT_MAX']) / 1000 if 'POWER_SUPPLY_CURRENT_MAX' in data else None})
            except (OSError, ValueError): continue
        return result
    return {'available': False}


if __name__ == '__main__':
    print(json.dumps(read_battery()))
