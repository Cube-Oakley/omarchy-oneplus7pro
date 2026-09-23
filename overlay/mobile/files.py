#!/usr/bin/env python3
"""Home-folder file helper for the Files app.

Every path is resolved and must stay inside a granted root. A symlink that
points outside those roots is not listed and cannot be opened or deleted.
The home grant does not include the rest of the system, even when the session
user's home is a privileged account.
"""
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time


def load_apps():
    # Installed copies are named omarchy-mobile-app, with no .py suffix.
    # The source tree keeps app.py so tests can import it directly.
    here = Path(__file__).resolve().parent
    for name in ('app.py', 'omarchy-mobile-app'):
        path = here / name
        if not path.is_file():
            continue
        loader = importlib.machinery.SourceFileLoader('omarchy_mobile_apps', str(path))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        module = importlib.util.module_from_spec(spec)
        loader.exec_module(module)
        return module
    raise ImportError('omarchy-mobile-app is not installed next to the file helper')


apps = load_apps()


PLACE_NAMES = ('Desktop', 'Documents', 'Downloads', 'Music', 'Pictures', 'Videos')
KINDS = {
    'image': {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.svg'},
    'text': {'.txt', '.md', '.log', '.json', '.qml', '.py', '.sh', '.conf', '.toml',
             '.csv', '.xml', '.yml', '.yaml', '.ini', '.css', '.js', '.html', '.service'},
    'audio': {'.mp3', '.ogg', '.flac', '.wav', '.m4a', '.opus'},
    'video': {'.mp4', '.mkv', '.webm', '.mov'},
    'archive': {'.zip', '.tar', '.gz', '.tgz', '.7z', '.xz', '.bz2'},
}


def home_roots(home=None):
    home = Path(home or Path.home()).resolve()
    roots = [home]
    for name in PLACE_NAMES:
        candidate = (home / name).resolve()
        if candidate.is_dir() and not contains(home, candidate):
            roots.append(candidate)
    return roots


def places(home, roots):
    home = Path(home).resolve()
    found = [{'name': 'Home', 'path': str(home)}]
    for name in PLACE_NAMES:
        candidate = (home / name)
        if not candidate.is_dir():
            continue
        resolved = candidate.resolve()
        if inside(resolved, roots):
            found.append({'name': name, 'path': str(resolved)})
    return found


def contains(root, path):
    root = root.resolve()
    path = path.resolve()
    return path == root or root in path.parents


def inside(path, roots):
    return any(contains(root, path) for root in roots)


def resolve_inside(raw, roots):
    path = Path(raw)
    if not path.is_absolute():
        raise ValueError('Path must be absolute')
    resolved = path.resolve()
    if not inside(resolved, roots):
        raise PermissionError('Outside the granted folders')
    return resolved


def component(name):
    if not name or name in ('.', '..') or '/' in name or '\x00' in name:
        raise ValueError('Name must be a single folder name')
    if len(name) > 255:
        raise ValueError('Name is too long')
    return name


def label_size(size):
    step = 1024.0
    if size < step:
        return f'{int(size)} B'
    for unit in ('KB', 'MB', 'GB', 'TB'):
        size /= step
        if size < step:
            return f'{size:.1f} {unit}'
    return f'{size:.1f} PB'


def kind_for(path, directory):
    if directory:
        return 'folder'
    suffix = path.suffix.lower()
    for kind, suffixes in KINDS.items():
        if suffix in suffixes:
            return kind
    return 'file'


def describe(path, display_name=None):
    try:
        stat = path.stat()
        size = stat.st_size
        modified = stat.st_mtime
    except OSError:
        size = 0
        modified = 0
    directory = path.is_dir()
    when = time.strftime('%d %b %Y', time.localtime(modified)) if modified else ''
    return {
        'name': display_name or path.name,
        'dir': directory,
        'kind': kind_for(path, directory),
        'size': '' if directory else label_size(size),
        'bytes': 0 if directory else size,
        'modified': when,
        'mtime': modified,
        'path': str(path),
    }


def roots_for(app_id='files'):
    if not apps.has_grant(app_id, 'files.home'):
        raise PermissionError('Home folder access is not granted')
    return home_roots()


def crumbs_for(resolved, roots, home):
    home = Path(home).resolve()
    chain = []
    current = resolved
    while inside(current, roots):
        chain.append({
            'name': 'Home' if current == home else current.name,
            'path': str(current),
        })
        if current == home or current.parent == current:
            break
        current = current.parent.resolve()
    chain.reverse()
    return chain


def snapshot(path, roots, order='name', hidden=False, home=None):
    if order not in ('name', 'modified', 'size'):
        raise ValueError('Sort must be name, modified, or size')
    resolved = resolve_inside(path, roots)
    if not resolved.is_dir():
        raise NotADirectoryError(str(resolved))
    home = Path(home or Path.home()).resolve()
    entries = []
    for child in resolved.iterdir():
        if not hidden and child.name.startswith('.'):
            continue
        try:
            target = child.resolve()
        except OSError:
            continue
        if not inside(target, roots):
            continue
        entries.append(describe(target, child.name))
    def ordering(item):
        if order == 'modified':
            return (not item['dir'], -item['mtime'])
        if order == 'size':
            return (not item['dir'], -item['bytes'])
        return (not item['dir'], item['name'].casefold())
    entries.sort(key=ordering)
    truncated = len(entries) > 500
    parent = resolved.parent.resolve()
    return {
        'ok': True,
        'path': str(resolved),
        'name': 'Home' if resolved == home else (resolved.name or str(resolved)),
        'parent': str(parent) if inside(parent, roots) else None,
        'crumbs': crumbs_for(resolved, roots, home),
        'truncated': truncated,
        'entries': entries[:500],
    }


def make_dir(path, name, roots, order='name', hidden=False):
    parent = resolve_inside(path, roots)
    folder = resolve_inside(parent / component(name), roots)
    folder.mkdir(parents=False, exist_ok=False)
    return snapshot(parent, roots, order, hidden)


def guarded(path, roots):
    target = resolve_inside(path, roots)
    if any(target == root.resolve() for root in roots):
        raise PermissionError('The home folder itself stays put')
    return target


def remove(path, roots, order='name', hidden=False):
    target = guarded(path, roots)
    parent = target.parent
    if target.is_dir():
        shutil.rmtree(target)
    else:
        target.unlink()
    return snapshot(parent, roots, order, hidden)


def rename(path, new_name, roots, order='name', hidden=False):
    target = guarded(path, roots)
    dest = resolve_inside(target.parent / component(new_name), roots)
    if dest.exists():
        raise FileExistsError('That name is already used')
    target.rename(dest)
    return snapshot(target.parent, roots, order, hidden)


def transfer(path, dest_dir, roots, copy, order='name', hidden=False):
    target = guarded(path, roots)
    folder = resolve_inside(dest_dir, roots)
    if not folder.is_dir():
        raise NotADirectoryError(str(folder))
    if folder == target or target in folder.parents:
        raise ValueError('A folder cannot be placed inside itself')
    dest = resolve_inside(folder / target.name, roots)
    if dest.exists():
        raise FileExistsError('That name is already used')
    if copy:
        if target.is_dir():
            shutil.copytree(target, dest)
        else:
            shutil.copy2(target, dest)
    else:
        shutil.move(str(target), str(dest))
    return snapshot(folder, roots, order, hidden)


def preview(path, roots):
    target = resolve_inside(path, roots)
    info = describe(target)
    info['ok'] = True
    info['text'] = None
    info['text_truncated'] = False
    if info['kind'] == 'text' and not info['dir'] and info['bytes'] <= 262144:
        lines = target.read_text(errors='replace').splitlines()
        info['text'] = '\n'.join(lines[:80])
        info['text_truncated'] = len(lines) > 80
    return info


def open_file(path, roots):
    target = resolve_inside(path, roots)
    if target.is_dir():
        raise IsADirectoryError(str(target))
    subprocess.Popen(['xdg-open', str(target)], start_new_session=True)
    return {'ok': True, 'path': str(target)}


def flag(argv, index, default):
    return argv[index] if len(argv) > index else default


def main(argv):
    action = argv[1] if len(argv) > 1 else ''
    try:
        roots = roots_for()
        home = Path.home().resolve()
        order = 'name'
        hidden = False
        if action == 'roots':
            print(json.dumps({
                'ok': True,
                'home': str(home),
                'roots': [str(root) for root in roots],
                'places': places(home, roots),
            }))
        elif action == 'list' and len(argv) >= 3:
            order = flag(argv, 3, 'name')
            hidden = flag(argv, 4, '0') == '1'
            print(json.dumps(snapshot(argv[2], roots, order, hidden, home)))
        elif action == 'mkdir' and len(argv) >= 4:
            print(json.dumps(make_dir(argv[2], argv[3], roots, flag(argv, 4, 'name'), flag(argv, 5, '0') == '1')))
        elif action == 'delete' and len(argv) >= 3:
            print(json.dumps(remove(argv[2], roots, flag(argv, 3, 'name'), flag(argv, 4, '0') == '1')))
        elif action == 'rename' and len(argv) >= 4:
            print(json.dumps(rename(argv[2], argv[3], roots, flag(argv, 4, 'name'), flag(argv, 5, '0') == '1')))
        elif action in ('move', 'copy') and len(argv) >= 4:
            print(json.dumps(transfer(argv[2], argv[3], roots, action == 'copy', flag(argv, 4, 'name'), flag(argv, 5, '0') == '1')))
        elif action == 'preview' and len(argv) == 3:
            print(json.dumps(preview(argv[2], roots)))
        elif action == 'open' and len(argv) == 3:
            print(json.dumps(open_file(argv[2], roots)))
        else:
            print('Usage: omarchy-mobile-files roots|list|mkdir|delete|rename|move|copy|preview|open ...', file=sys.stderr)
            return 2
        return 0
    except (OSError, ValueError, PermissionError) as error:
        print(json.dumps({'ok': False, 'error': str(error)}))
        return 1


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
