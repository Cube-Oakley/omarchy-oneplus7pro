#!/usr/bin/env python3
"""Install Omarchy themes through one hook.

Desktop Omarchy's `omarchy theme install` is used when it is on PATH. This
minimal phone image does not ship that package, so the same URL check, theme
name and `~/.config/omarchy/themes` clone are done here, then the mobile
theme helper applies the palette. A pairing daemon should call this command,
not a second installer:

  omarchy-mobile-theme-install url GIT_URL
  omarchy-mobile-theme-install name CATALOG_NAME
"""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import urllib.request

HOME = Path.home()
CONFIG = Path(os.getenv("XDG_CONFIG_HOME", HOME / ".config"))
CACHE = Path(os.getenv("XDG_CACHE_HOME", HOME / ".cache")) / "omarchy-mobile"
CATALOG_URL = "https://omarchy.us/themes"
CATALOG_FILE = CACHE / "theme-catalog.json"
THEME_NAME = re.compile(r"[a-z0-9_][a-z0-9._+-]*")
TRANSPORTS = {"ssh", "git", "git+ssh", "ssh+git", "http", "https", "ftp", "ftps", "file"}
CARD = re.compile(
    r'<a href="(https://github.com/[^"]+)"[^>]*>\s*<img src="(/assets/themes/[^"]+)" alt="([^"]*?) theme screenshot"',
    re.I,
)


def fail(message):
    raise ValueError(message)


def check_url(url):
    if not isinstance(url, str) or not url or url.startswith("-") or re.match(r"^[A-Za-z0-9][A-Za-z0-9+.-]*::", url):
        fail(f"{url!r} names a git option or transport helper, not a repository.")
    scheme = re.match(r"^([A-Za-z0-9][A-Za-z0-9+.-]*)://", url)
    if scheme and scheme.group(1).lower() not in TRANSPORTS:
        fail(f"{url!r} names the {scheme.group(1)!r} transport, which Omarchy does not clone from.")
    return url


def theme_name(url):
    path = url
    if "://" not in path and ":" in path and "/" not in path.split(":", 1)[0]:
        path = path.split(":", 1)[1]
    name = os.path.basename(path.rstrip("/"))
    if name.endswith(".git"):
        name = name[:-4]
    name = re.sub(r"^omarchy-", "", name, flags=re.I)
    name = re.sub(r"-theme$", "", name, flags=re.I).lower()
    if not THEME_NAME.fullmatch(name):
        fail(f"{url!r} does not give a usable theme name.")
    return name


def installed_names():
    root = CONFIG / "omarchy/themes"
    names = set()
    if root.is_dir():
        for path in root.glob("*/colors.toml"):
            if THEME_NAME.fullmatch(path.parent.name):
                names.add(path.parent.name)
    return names


def parse_catalog(html):
    themes = []
    seen = set()
    for repo, image, label in CARD.findall(html):
        try:
            name = theme_name(repo)
        except ValueError:
            continue
        if name in seen:
            continue
        seen.add(name)
        themes.append({
            "name": label.strip() or name,
            "id": name,
            "repo": repo.rstrip("/"),
            "preview": "https://omarchy.us" + image,
        })
    themes.sort(key=lambda item: item["name"].lower())
    return themes


def catalog(refresh=False):
    CACHE.mkdir(parents=True, exist_ok=True)
    if refresh or not CATALOG_FILE.is_file():
        request = urllib.request.Request(CATALOG_URL, headers={"User-Agent": "Mozilla/5.0 omarchy-mobile"})
        with urllib.request.urlopen(request, timeout=20) as response:
            html = response.read().decode()
        themes = parse_catalog(html)
        if not themes:
            fail("Theme catalog did not list any themes.")
        CATALOG_FILE.write_text(json.dumps(themes) + "\n")
    themes = json.loads(CATALOG_FILE.read_text())
    present = installed_names()
    for item in themes:
        item["installed"] = item["id"] in present
    return themes


def lookup(query):
    needle = query.strip().lower()
    matches = [item for item in catalog() if item["id"] == needle or item["name"].lower() == needle]
    if not matches:
        matches = [item for item in catalog() if needle in item["name"].lower()]
    if len(matches) != 1:
        fail(f"Catalog has {len(matches)} themes matching {query!r}.")
    return matches[0]

def take_lines(pending, chunk):
    pending += chunk.replace(b"\r", b"\n")
    lines = []
    while b"\n" in pending:
        raw, pending = pending.split(b"\n", 1)
        text = raw.decode(errors="replace").strip()
        if text:
            lines.append(text)
    return lines, pending


def log(text):
    print(text, file=sys.stderr, flush=True)


def stream(command):
    proc = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    pending = b""
    while True:
        chunk = proc.stdout.read(256)
        if not chunk:
            break
        lines, pending = take_lines(pending, chunk)
        for line in lines:
            if not line.startswith("{"):
                log(line)
    for line in take_lines(pending, b"\n")[0]:
        if not line.startswith("{"):
            log(line)
    code = proc.wait()
    if code != 0:
        raise subprocess.CalledProcessError(code, command)


def install_url(url):
    url = check_url(url.strip())
    name = theme_name(url)
    log(f"Installing {name}")
    omarchy = shutil.which("omarchy")
    if omarchy:
        log(f"omarchy theme install {url}")
        stream([omarchy, "theme", "install", url])
    else:
        dest = CONFIG / "omarchy/themes" / name
        if dest.exists():
            shutil.rmtree(dest)
        dest.parent.mkdir(parents=True, exist_ok=True)
        log(f"Cloning {url}")
        try:
            stream(["git", "clone", "--progress", "--depth", "1", "--", url, str(dest)])
        except subprocess.CalledProcessError:
            shutil.rmtree(dest, ignore_errors=True)
            raise
        if not (dest / "colors.toml").is_file():
            shutil.rmtree(dest, ignore_errors=True)
            fail(f"{name} has no colors.toml.")
        log(f"Applying {name}")
        helper = HOME / ".local/bin/omarchy-mobile-theme"
        stream([str(helper), "set", name])
    log("Installed")
    return {"installed": True, "id": name, "repo": url}


def hook():
    command = str(HOME / ".local/bin/omarchy-mobile-theme-install")
    return {
        "install-url": [command, "url", "GIT_URL"],
        "install-name": [command, "name", "CATALOG_NAME"],
        "idempotent": True,
        "applies": True,
        "note": "Pairing should call this helper when a desktop installs a theme. Do not clone beside it.",
    }


def main():
    args = sys.argv[1:]
    if args == ["catalog"]:
        print(json.dumps({"themes": catalog(refresh=True)}))
    elif args == ["hook"]:
        print(json.dumps(hook()))
    elif len(args) == 2 and args[0] == "url":
        print(json.dumps(install_url(args[1])))
    elif len(args) == 2 and args[0] == "name":
        print(json.dumps(install_url(lookup(args[1])["repo"])))
    else:
        fail("Usage: omarchy-mobile-theme-install catalog|hook|url GIT_URL|name CATALOG_NAME")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
