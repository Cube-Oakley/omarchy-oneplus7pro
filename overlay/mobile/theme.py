#!/usr/bin/env python3
"""Adapt standard Omarchy colors.toml palettes without executing theme code."""
import json
import fcntl
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tomllib

HOME = Path.home()
CONFIG = Path(os.getenv("XDG_CONFIG_HOME", HOME / ".config"))
STATE = Path(os.getenv("XDG_STATE_HOME", HOME / ".local/state"))
DATA = Path(os.getenv("XDG_DATA_HOME", HOME / ".local/share"))
MOBILE = STATE / "omarchy-mobile"
ROOTS = [DATA / "omarchy-mobile/themes", Path(os.getenv("OMARCHY_PATH", "/usr/share/omarchy")) / "themes", CONFIG / "omarchy/themes"]
DEFAULTS = dict(background="#1a1b26", foreground="#a9b1d6", bright_foreground="#c0caf5", accent="#7aa2f7", selection="#292e42", muted="#414868", lighter_background="#24283b")


def write_changed(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_text() == content:
        return False
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(content)
    temporary.replace(path)
    return True


def themes():
    result = {}
    for root in ROOTS:
        for file in sorted(root.glob("*/colors.toml")):
            if re.fullmatch(r"[a-z0-9-]+", file.parent.name):
                result[file.parent.name] = file
    return result


IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp"}


def theme_context():
    available = themes()
    selected_file = MOBILE / "selected-theme"
    selected = selected_file.read_text().strip() if selected_file.exists() else "tokyo-night"
    file = available.get(selected)
    current = None
    # Support generated modern state and the earlier current-theme symlink.
    for candidate in [STATE / "omarchy/current/theme", CONFIG / "omarchy/current/theme"]:
        if (candidate / "colors.toml").is_file():
            current = candidate
            file = current / "colors.toml"
            namefile = current.parent / "theme.name"
            selected = namefile.read_text().strip() if namefile.exists() else current.resolve().name
            break
    return available, selected, file, current


def image_file(path):
    return path.is_file() and path.resolve().suffix.lower() in IMAGE_SUFFIXES


def wallpaper_choices(selected, current):
    slug = selected.lower().replace(" ", "-")
    # Match Omarchy's stock + user overlay model by filename.
    merged = {}
    for root in ROOTS:
        for path in sorted((root / slug / "backgrounds").glob("*")):
            if image_file(path):
                merged[path.name] = path.resolve()
    if current:
        for path in sorted((current / "backgrounds").glob("*")):
            if image_file(path):
                merged[path.name] = path.resolve()
    for path in sorted((CONFIG / "omarchy/backgrounds" / slug).glob("*")):
        if image_file(path):
            merged[path.name] = path.resolve()
    return list(dict.fromkeys(merged[name] for name in sorted(merged)))


def saved_backgrounds():
    try:
        value = json.loads((MOBILE / "backgrounds.json").read_text())
        return value if isinstance(value, dict) else {}
    except (FileNotFoundError, ValueError):
        return {}


def wallpaper_state(selected, current, advance=False):
    choices = wallpaper_choices(selected, current)
    saved = saved_backgrounds()
    chosen = None
    if current:
        link = current.parent / "background"
        if image_file(link):
            chosen = link.resolve()
    else:
        remembered = saved.get(selected)
        if isinstance(remembered, str) and Path(remembered) in choices:
            chosen = Path(remembered)
    if advance:
        if current:
            raise ValueError("Use Omarchy's background command to change its current state")
        if not choices:
            raise ValueError("This theme has no wallpapers")
        index = choices.index(chosen) if chosen in choices else -1
        chosen = choices[(index + 1) % len(choices)]
    elif chosen is None and choices:
        chosen = choices[0]
    if not current and chosen:
        saved[selected] = str(chosen)
        write_changed(MOBILE / "backgrounds.json", json.dumps(saved, indent=2) + "\n")
    return {
        "path": str(chosen) if chosen else "",
        "url": chosen.as_uri() + "?v=" + str(chosen.stat().st_mtime_ns) if chosen else "",
        "name": chosen.name if chosen else "",
        "index": choices.index(chosen) + 1 if chosen in choices else 0,
        "count": len(choices),
    }


def palette(file):
    data = tomllib.loads(file.read_text()) if file else {}
    # Support both current semantic names and older Omarchy ANSI palettes.
    aliases = {"accent": "color4", "muted": "color8", "bright_foreground": "color15"}
    colors = dict(DEFAULTS)
    for key, value in data.items():
        if isinstance(value, str) and re.fullmatch(r"#[0-9a-fA-F]{6}", value):
            colors[key] = value
    for key, alias in aliases.items():
        if key not in data and alias in colors:
            colors[key] = colors[alias]
    if "lighter_background" not in data:
        bg = [int(colors["background"][i:i+2], 16) for i in (1, 3, 5)]
        fg = [int(colors["foreground"][i:i+2], 16) for i in (1, 3, 5)]
        colors["lighter_background"] = "#" + "".join(f"{round(a*.9+b*.1):02x}" for a, b in zip(bg, fg))
    return colors


def signal_owned(name, sig):
    result = subprocess.run(["pgrep", "-u", str(os.getuid()), "-x", name], capture_output=True, text=True)
    for pid in result.stdout.split():
        try:
            os.kill(int(pid), sig)
        except ProcessLookupError:
            pass


def sync():
    available, selected, file, current = theme_context()
    colors = palette(file)
    devicefile = CONFIG / "omarchy-mobile/device.json"
    device = json.loads(devicefile.read_text()) if devicefile.exists() else {}
    result = {"name": selected, "colors": colors, "themes": sorted(available), "device": device, "wallpaper": wallpaper_state(selected, current)}
    border = 'hl.config({general={col={active_border={colors={"rgba(' + colors['accent'][1:] + 'ff)"},angle=0},inactive_border="rgba(' + colors['muted'][1:] + 'ff)"}}})'
    lua = 'dofile(' + json.dumps(str(DATA / 'omarchy-mobile/hypr-mobile.lua')) + ')\n'
    scale = device.get('scale')
    if isinstance(scale, (int, float)) and not isinstance(scale, bool) and 0.5 <= scale <= 5:
        lua += 'hl.monitor({output="",mode="preferred",position="auto",scale=' + str(scale) + '})\n'
    lua += border + '\n'
    shortcut = device.get('terminalShortcut', '')
    if re.fullmatch(r'[A-Z0-9 +]+', shortcut):
        lua += 'hl.unbind(' + json.dumps(shortcut) + ')\nhl.bind(' + json.dumps(shortcut) + ', hl.dsp.exec_cmd("env KITTY_MOBILE_TOUCH=1 kitty"))\n'
    write_changed(CONFIG / 'hypr/mobile.lua', lua)
    try:
        previous = json.loads((MOBILE / "palette.json").read_text())
    except (FileNotFoundError, ValueError):
        previous = {}
    # Optional trusted device integration, separate from imported theme assets.
    wallpaper_hook = CONFIG / "omarchy-mobile/wallpaper-apply"
    if previous.get("wallpaper") != result["wallpaper"] and os.access(wallpaper_hook, os.X_OK):
        subprocess.run([str(wallpaper_hook), result["wallpaper"]["path"]], check=True,
                       stdout=subprocess.DEVNULL)
    write_changed(MOBILE / "palette.json", json.dumps(result, indent=2) + "\n")
    # Wallpaper changes must not restart the keyboard or reconfigure terminals.
    if previous.get("colors") != colors:
        lines = [f"background {colors['background']}", f"foreground {colors['foreground']}", f"cursor {colors['accent']}",
                 f"selection_background {colors.get('selection_background', colors['selection'])}", f"selection_foreground {colors.get('selection_foreground', colors['bright_foreground'])}"]
        ansi = ["background", "red", "green", "yellow", "blue", "magenta", "cyan", "foreground", "muted", "bright_red", "bright_green", "bright_yellow", "bright_blue", "bright_magenta", "bright_cyan", "bright_foreground"]
        for i, name in enumerate(ansi):
            lines.append(f"color{i} {colors.get(name, colors.get('color'+str(i), colors['foreground']))}")
        write_changed(CONFIG / "kitty/mobile-theme.conf", "\n".join(lines) + "\n")
        signal_owned("kitty", signal.SIGUSR1)
        # Keyboard colors are startup options. Restart only this helper's PID.
        runtime = Path(os.getenv("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
        pidfile = runtime / "omarchy-mobile-keyboard.pid"
        try:
            pid = int(pidfile.read_text())
            if Path(f"/proc/{pid}/comm").read_text().strip() == "wvkbd-mobintl":
                os.kill(pid, signal.SIGTERM)
        except (FileNotFoundError, ValueError, ProcessLookupError):
            pass
        helper = HOME / ".local/bin/omarchy-mobile-keyboard"
        if helper.exists() and os.getenv("WAYLAND_DISPLAY"):
            subprocess.run([str(helper), "start"], stdout=subprocess.DEVNULL, check=True)
        # Only update the border colors, retaining the user's layout/bindings.
        subprocess.run(["hyprctl", "eval", border], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return result


def main():
    args = sys.argv[1:]
    delegated = False
    if len(args) == 2 and args[0] == "set":
        if args[1] not in themes():
            raise ValueError("Unknown installed theme")
        if shutil.which("omarchy"):
            # Run outside our lock: Omarchy hooks may call mobile sync.
            subprocess.run(["omarchy", "theme", "set", args[1]], check=True, stdout=sys.stderr)
            delegated = True
    elif args == ["background", "next"]:
        if shutil.which("omarchy"):
            subprocess.run(["omarchy", "theme", "bg", "next"], check=True, stdout=sys.stderr)
            delegated = True
    elif args not in ([], ["sync"]):
        raise ValueError("Usage: omarchy-mobile-theme [sync|set THEME|background next]")
    MOBILE.mkdir(parents=True, exist_ok=True)
    with (MOBILE / "theme.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if not delegated and len(args) == 2 and args[0] == "set":
            write_changed(MOBILE / "selected-theme", args[1] + "\n")
        elif not delegated and args == ["background", "next"]:
            _, selected, _, current = theme_context()
            wallpaper_state(selected, current, advance=True)
        print(json.dumps(sync()))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
