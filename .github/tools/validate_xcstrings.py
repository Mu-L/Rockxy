#!/usr/bin/env python3
"""Deterministic validator for Rockxy Xcode String Catalogs (.xcstrings).

Checks, for every catalog passed on the command line (defaults to the two
canonical catalogs):

  * the file is valid JSON with sourceLanguage == "en";
  * every translatable entry has a non-empty translation for each required
    language (default: zh-Hans) -- this is the coverage gate;
  * no translation value is empty or whitespace-only;
  * printf-style placeholders and positional arguments match between the
    source string and each translation (placeholder parity);
  * when `xcrun xcstringstool` is available, each catalog compiles cleanly.

The script needs no third-party packages and no secrets, so it is safe to run
on untrusted fork pull requests. Exit code is non-zero if any check fails.

Usage:
    python3 .github/tools/validate_xcstrings.py [--require zh-Hans[,de,...]] [catalog ...]
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# %@  %lld  %1$@  %2$lld  %.2f  %d ... (positional prefix captured separately)
PLACEHOLDER_RE = re.compile(
    r"%(\d+\$)?[-+ 0#]*[0-9]*(?:\.[0-9]+)?(?:hh|h|ll|l|q|L|z|j|t)?[@dDiuUxXoOeEfFgGaAcCsSpn%]"
)

DEFAULT_CATALOGS = [
    "Rockxy/Localizable.xcstrings",
    "Rockxy/InfoPlist.xcstrings",
]


def placeholder_multiset(text: str) -> list[str]:
    """Return the sorted list of placeholder tokens, ignoring literal %%."""
    tokens = []
    for match in PLACEHOLDER_RE.finditer(text):
        token = match.group(0)
        if token == "%%":
            continue
        # Normalise away width/flags so "%lld" and "%1$lld" compare by conversion.
        positional = match.group(1) or ""
        conversion = token[-1]
        length = ""
        for cand in ("hh", "ll", "h", "l", "q", "L", "z", "j", "t"):
            if cand in token[:-1]:
                length = cand
                break
        tokens.append(f"{positional}{length}{conversion}")
    return sorted(tokens)


def collect_units(node: object, path: tuple[str, ...] = ()) -> dict[tuple[str, ...], str]:
    """Return every concrete string-unit value keyed by its catalog path.

    Walking every dictionary, rather than only `variations`, also covers catalog
    substitutions and future nested Xcode structures. Comparing each path
    independently prevents a missing placeholder in one plural branch from being
    hidden by an extra placeholder in another branch.
    """
    units: dict[tuple[str, ...], str] = {}
    if not isinstance(node, dict):
        return units

    string_unit = node.get("stringUnit")
    if isinstance(string_unit, dict) and isinstance(string_unit.get("value"), str):
        units[path] = string_unit["value"]

    for key, value in node.items():
        if key != "stringUnit":
            units.update(collect_units(value, path + (key,)))
    return units


def source_units(key: str, entry: dict) -> dict[tuple[str, ...], str]:
    """Return English units, falling back to the catalog key when implicit."""
    en = entry.get("localizations", {}).get("en")
    if isinstance(en, dict):
        units = collect_units(en)
        if units:
            return units
    return {(): key}


def is_translatable(entry: dict) -> bool:
    return entry.get("shouldTranslate", True) is not False


def validate_catalog(path: Path, required: list[str]) -> list[str]:
    errors: list[str] = []
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as exc:
        return [f"{path}: cannot read file ({exc})"]

    try:
        catalog = json.loads(raw)
    except json.JSONDecodeError as exc:
        return [f"{path}: invalid JSON ({exc})"]

    if catalog.get("sourceLanguage") != "en":
        errors.append(f"{path}: sourceLanguage must be \"en\", got {catalog.get('sourceLanguage')!r}")

    strings = catalog.get("strings")
    if not isinstance(strings, dict):
        errors.append(f"{path}: missing \"strings\" object")
        return errors

    for key, entry in sorted(strings.items()):
        if not isinstance(entry, dict):
            errors.append(f"{path}: entry {key!r} is not an object")
            continue
        localizations = entry.get("localizations", {})
        translatable = is_translatable(entry)
        expected_units = source_units(key, entry)

        for lang in required:
            if not translatable:
                continue
            node = localizations.get(lang)
            if not isinstance(node, dict):
                errors.append(f"{path}: {key!r} missing {lang} translation")
                continue
            translated_units = collect_units(node)
            if not translated_units:
                errors.append(f"{path}: {key!r} has no {lang} value")
                continue
            if translated_units.keys() != expected_units.keys():
                errors.append(
                    f"{path}: {key!r} variation paths differ for {lang} "
                    f"(source={sorted(expected_units)}, {lang}={sorted(translated_units)})"
                )
                continue
            for unit_path, value in translated_units.items():
                if value.strip() == "":
                    errors.append(f"{path}: {key!r} has an empty {lang} value at {unit_path}")
                src_tokens = placeholder_multiset(expected_units[unit_path])
                translated_tokens = placeholder_multiset(value)
                if translated_tokens != src_tokens:
                    errors.append(
                        f"{path}: {key!r} placeholder mismatch for {lang} at {unit_path} "
                        f"(source={src_tokens}, {lang}={translated_tokens})"
                    )
    return errors


def compile_catalog(path: Path) -> list[str]:
    """Compile the catalog with xcstringstool when the toolchain is present.

    Absence of the toolchain (non-macOS, no Xcode) is not a failure; only an
    actual compile error is. This keeps the check runnable anywhere.
    """
    if shutil.which("xcrun") is None:
        return []
    probe = subprocess.run(
        ["xcrun", "--find", "xcstringstool"],
        capture_output=True,
        text=True,
        check=False,
    )
    if probe.returncode != 0:
        print(f"note: xcstringstool not found; skipping compile of {path}", file=sys.stderr)
        return []
    with tempfile.TemporaryDirectory(prefix="rockxy-xcstrings-") as temporary_dir:
        result = subprocess.run(
            ["xcrun", "xcstringstool", "compile", "--output-directory", temporary_dir, str(path)],
            capture_output=True,
            text=True,
            check=False,
        )
    if result.returncode != 0:
        message = (result.stderr or result.stdout).strip()
        return [f"{path}: xcstringstool compile failed ({message})"]
    return []


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate Rockxy .xcstrings catalogs.")
    parser.add_argument(
        "--require",
        default="zh-Hans",
        help="Comma-separated languages that must be fully translated (default: zh-Hans).",
    )
    parser.add_argument(
        "--no-compile",
        action="store_true",
        help="Skip the optional xcstringstool compile step.",
    )
    parser.add_argument("catalogs", nargs="*", default=DEFAULT_CATALOGS)
    args = parser.parse_args()

    required = [lang.strip() for lang in args.require.split(",") if lang.strip()]
    catalogs = args.catalogs or DEFAULT_CATALOGS

    all_errors: list[str] = []
    for name in catalogs:
        path = Path(name)
        if not path.exists():
            all_errors.append(f"{path}: catalog not found")
            continue
        all_errors.extend(validate_catalog(path, required))
        if not args.no_compile:
            all_errors.extend(compile_catalog(path))

    if all_errors:
        print("Localization validation FAILED:", file=sys.stderr)
        for err in all_errors:
            print(f"  - {err}", file=sys.stderr)
        print(f"\n{len(all_errors)} problem(s) found.", file=sys.stderr)
        return 1

    print(f"Localization validation passed for {len(catalogs)} catalog(s); required: {', '.join(required)}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
