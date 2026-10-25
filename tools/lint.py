#!/usr/bin/env python3
"""Repository checks that need no Noctalia install.

- every *.toml parses (and spotify-launcher.conf, which is TOML)
- every *.json parses
- each noctalia-plugins/<name>/plugin.toml has the required fields, a valid
  version, existing entry scripts and relative requires
- every translation key a manifest or a .luau script uses exists in
  translations/en.json, and every translation file has the same keys as en.json
"""

import json
import re
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ENTRY_TABLES = ("widget", "service", "panel", "shortcut", "launcher_provider", "desktop_widget", "layer")
TR_CALL = re.compile(r"noctalia\.(trp?)\(\s*\"([^\"]+)\"")
REQUIRE = re.compile(r"require\(\s*\"([^\"]+)\"\s*\)")
VERSION = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")

errors: list[str] = []


def error(path: Path, msg: str) -> None:
    errors.append(f"{path.relative_to(ROOT)}: {msg}")


def flatten(data: dict, prefix: str = "") -> set[str]:
    keys = set()
    for key, value in data.items():
        full = f"{prefix}{key}"
        if isinstance(value, dict):
            keys |= flatten(value, full + ".")
        else:
            keys.add(full)
    return keys


def tracked(pattern: str) -> list[Path]:
    return sorted(p for p in ROOT.rglob(pattern) if ".git" not in p.parts)


def check_parsing() -> None:
    for path in tracked("*.toml") + [ROOT / "config" / "spotify-launcher.conf"]:
        try:
            tomllib.loads(path.read_text(encoding="utf-8"))
        except tomllib.TOMLDecodeError as exc:
            error(path, f"invalid TOML: {exc}")
    for path in tracked("*.json"):
        try:
            json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            error(path, f"invalid JSON: {exc}")


def setting_keys(table: dict) -> list[str]:
    keys = []
    for setting in table.get("setting", []):
        for field in ("label_key", "description_key"):
            if field in setting:
                keys.append(setting[field])
        for option in setting.get("options", []):
            if "label_key" in option:
                keys.append(option["label_key"])
    return keys


def check_plugin(plugin_dir: Path) -> None:
    manifest_path = plugin_dir / "plugin.toml"
    try:
        manifest = tomllib.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, tomllib.TOMLDecodeError):
        error(manifest_path, "missing or unparsable manifest")
        return

    for field in ("id", "name", "version", "plugin_api"):
        if field not in manifest:
            error(manifest_path, f"missing required field '{field}'")
    if not VERSION.match(str(manifest.get("version", ""))):
        error(manifest_path, "version must be MAJOR.MINOR.PATCH")
    if not str(manifest.get("id", "")).endswith("/" + plugin_dir.name):
        error(manifest_path, f"id should end with '/{plugin_dir.name}'")

    used = setting_keys(manifest)
    for kind in ENTRY_TABLES:
        for entry in manifest.get(kind, []):
            script = plugin_dir / entry.get("entry", "")
            if not script.is_file():
                error(manifest_path, f"[[{kind}]] '{entry.get('id')}' entry '{entry.get('entry')}' not found")
            used += setting_keys(entry)

    plural: set[str] = set()
    for script in plugin_dir.rglob("*.luau"):
        source = script.read_text(encoding="utf-8")
        for fn, key in TR_CALL.findall(source):
            if fn == "trp":
                plural.add(key)
            else:
                used.append(key)
        for target in REQUIRE.findall(source):
            if not (script.parent / target).resolve().is_file():
                error(script, f"require target '{target}' not found")

    translations = plugin_dir / "translations"
    en_path = translations / "en.json"
    if not en_path.is_file():
        if used or plural:
            error(plugin_dir / "plugin.toml", "uses translation keys but has no translations/en.json")
        return
    en = flatten(json.loads(en_path.read_text(encoding="utf-8")))

    for key in sorted(set(used)):
        if key not in en:
            error(en_path, f"missing key '{key}'")
    for key in sorted(plural):
        if key not in en and not {f"{key}.one", f"{key}.other"} <= en:
            error(en_path, f"missing plural key '{key}' (or '{key}.one' / '{key}.other')")

    for other in sorted(translations.glob("*.json")):
        if other == en_path:
            continue
        keys = flatten(json.loads(other.read_text(encoding="utf-8")))
        for key in sorted(en - keys):
            error(other, f"missing key '{key}' (present in en.json)")
        for key in sorted(keys - en):
            error(other, f"extra key '{key}' (not in en.json)")


def main() -> int:
    check_parsing()
    for plugin_dir in sorted((ROOT / "noctalia-plugins").iterdir()):
        if plugin_dir.is_dir():
            check_plugin(plugin_dir)
    for line in errors:
        print(line)
    print(f"{len(errors)} problem(s)" if errors else "all checks passed")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
