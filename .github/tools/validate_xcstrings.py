#!/usr/bin/env python3
"""Deterministic validator for Rockxy Xcode String Catalogs (.xcstrings).

Checks, for every catalog passed on the command line (defaults to the two
canonical catalogs):

  * the file is valid JSON with sourceLanguage == "en";
  * every translatable entry has a non-empty translation for each required
    language (default: every locale discovered across the canonical catalogs,
    plus the shipped zh-Hans baseline) -- this is the coverage gate;
  * no translation value is empty or whitespace-only;
  * printf-style placeholders and positional arguments match between the
    source string and each translation (placeholder parity);
  * direct, non-interpolated Swift String(localized:) keys exist in the app catalog;
  * high-confidence zh-Hans terminology rules remain contextually correct;
  * locales in the canonical catalogs match the Xcode project's knownRegions;
  * when `xcrun xcstringstool` is available, each catalog compiles cleanly.

The script needs no third-party packages and no secrets, so it is safe to run
on untrusted fork pull requests. Exit code is non-zero if any check fails.

Usage:
    python3 .github/tools/validate_xcstrings.py [--require all|zh-Hans[,de,...]] [catalog ...]
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
BASELINE_LANGUAGES = {"zh-Hans"}
DEFAULT_PROJECT_FILE = Path("Rockxy.xcodeproj/project.pbxproj")
DEFAULT_SWIFT_SOURCE_ROOT = Path("Rockxy")
DIRECT_LOCALIZED_LITERAL_RE = re.compile(r'String\s*\(\s*localized:\s*"([^"\\]*)"', re.MULTILINE)

# Simplified-Chinese glossary gate. Each rule is narrow and deterministic: it
# fires only when the *English source* proves the meaning, then forbids a term
# whose use in that context is a known mistranslation. "Code" is intentionally
# excluded because it is context-dependent (HTTP status vs. the VS Code app);
# call-site routing handles it, not a value-wide rule.
#
# Exact English keys whose "token" is an AI model token (never an auth/pairing
# token), so the Simplified-Chinese value must keep the English word "token"
# rather than the auth-only 令牌.
ZH_HANS_AI_TOKEN_KEYS = frozenset(
    {
        "%@ tokens",
        "%lld input · %lld output tokens",
        "Context window tokens",
        "Maximum output tokens",
        "tokens",
        "tokens per response",
        "Compare model, tokens, finish reason, and latency against adjacent retries.",
        "Check event count, final event, interruption signs, and first-token/overall duration.",
        "Rockxy can identify this AI app session, but model, tokens, and tools need decrypted API evidence.",
        "SSE cadence is shown from captured events. Token boundaries stay unavailable unless the provider exposes them.",
        "Rockxy uses 8,192 tokens by default and limits local inference to 32,768 tokens to avoid excessive memory pressure.",
    }
)


def zh_hans_glossary_errors(path: Path, key: str, source: str, value: str, unit_path: tuple[str, ...]) -> list[str]:
    """Deterministic Simplified-Chinese terminology checks proven by the English source.

    Only forbid-rules are applied so unrelated future strings are never coerced;
    each rule is gated on an unambiguous English trigger.
    """
    lowered = source.lower()
    semantic_context = f"{key} {source}".lower()
    is_certificate_pinning = "certificate pinning" in lowered or "pins certificate" in lowered
    checks: list[tuple[bool, tuple[str, ...], str]] = [
        # redaction/redacted/redact -> 脱敏/已脱敏 (never 遮盖/隐去).
        ("redact" in lowered, ("遮盖", "隐去"), "redaction must use 脱敏/已脱敏"),
        # certificate pinning -> 证书固定 (never 锁定).
        (is_certificate_pinning, ("锁定",), "certificate pinning must use 固定"),
        # The named Compose feature stays "Compose" (never 编写).
        ("Compose" in source, ("编写",), "named Compose feature must stay Compose"),
        # Protobuf wire format -> 线格式 (never 线路格式).
        ("wire format" in lowered or "wire-format" in lowered, ("线路格式",), "Protobuf wire format must use 线格式"),
        # AI model token(s) -> token (never the auth-only 令牌).
        (key in ZH_HANS_AI_TOKEN_KEYS, ("令牌",), "AI model token must use token, not 令牌"),
    ]
    errors: list[str] = []
    for applies, banned, label in checks:
        if not applies:
            continue
        for term in banned:
            if term in value:
                errors.append(
                    f"{path}: {key!r} zh-Hans glossary at {unit_path}: {label} "
                    f"(found {term!r} in {value!r})"
                )
    requirements: list[tuple[bool, str, str]] = [
        ("status code" in semantic_context, "状态码", "HTTP status code must use 状态码"),
        ("redact" in lowered, "脱敏", "redaction must use 脱敏/已脱敏"),
        (is_certificate_pinning, "固定", "certificate pinning must use 固定"),
        ("Compose" in source, "Compose", "named Compose feature must stay Compose"),
        (
            "wire format" in lowered or "wire-format" in lowered,
            "线格式",
            "Protobuf wire format must use 线格式",
        ),
        (key in ZH_HANS_AI_TOKEN_KEYS, "token", "AI model token must use token"),
    ]
    for applies, required, label in requirements:
        if applies and required not in value:
            errors.append(
                f"{path}: {key!r} zh-Hans glossary at {unit_path}: {label} "
                f"(missing {required!r} in {value!r})"
            )
    return errors


def validate_swift_literal_coverage(source_root: Path, catalog_path: Path) -> list[str]:
    """Require direct, non-interpolated String(localized:) keys to exist in the catalog."""
    try:
        catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return [f"{catalog_path}: cannot check Swift literal coverage ({exc})"]
    strings = catalog.get("strings")
    if not isinstance(strings, dict):
        return [f"{catalog_path}: cannot check Swift literal coverage (missing strings object)"]

    errors: list[str] = []
    for source_path in sorted(source_root.rglob("*.swift")):
        try:
            source = source_path.read_text(encoding="utf-8")
        except OSError as exc:
            errors.append(f"{source_path}: cannot read Swift source ({exc})")
            continue
        for match in DIRECT_LOCALIZED_LITERAL_RE.finditer(source):
            key = match.group(1)
            if key not in strings:
                line = source.count("\n", 0, match.start()) + 1
                errors.append(f"{source_path}:{line}: localized key {key!r} is missing from {catalog_path}")
    return errors


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


def catalog_languages(paths: list[Path]) -> list[str]:
    """Return the union of translated locales across all readable catalogs.

    Invalid files are left to validate_catalog(), which reports actionable errors.
    """
    languages: set[str] = set()
    for path in paths:
        try:
            catalog = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue

        source_language = catalog.get("sourceLanguage")
        strings = catalog.get("strings")
        if not isinstance(strings, dict):
            continue
        for entry in strings.values():
            if not isinstance(entry, dict) or not is_translatable(entry):
                continue
            localizations = entry.get("localizations")
            if not isinstance(localizations, dict):
                continue
            languages.update(
                language
                for language in localizations
                if isinstance(language, str) and language and language != source_language
            )
    return sorted(languages)


def discover_languages(paths: list[Path]) -> list[str]:
    """Return every catalog locale plus the shipped baseline.

    The baseline prevents a pull request from bypassing coverage by deleting the
    only shipped translation from both catalogs. Taking the union means a locale
    added to just one catalog becomes required in every catalog in the same run.
    """
    return sorted(set(catalog_languages(paths)) | BASELINE_LANGUAGES)


def project_languages(path: Path) -> list[str]:
    """Read translatable locale identifiers from the Xcode knownRegions block."""
    text = path.read_text(encoding="utf-8")
    match = re.search(r"\bknownRegions\s*=\s*\((.*?)\);", text, re.DOTALL)
    if match is None:
        raise ValueError("missing knownRegions block")

    languages: set[str] = set()
    for raw_line in match.group(1).splitlines():
        token = raw_line.split("/*", 1)[0].strip().rstrip(",").strip()
        if not token:
            continue
        if token.startswith('"') and token.endswith('"'):
            token = json.loads(token)
        if token not in {"Base", "en"}:
            languages.add(token)
    return sorted(languages)


def validate_project_languages(paths: list[Path], project_path: Path) -> list[str]:
    """Require the canonical catalogs and Xcode project to declare the same locales."""
    try:
        regions = set(project_languages(project_path))
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        return [f"{project_path}: cannot read knownRegions ({exc})"]

    locales = set(catalog_languages(paths))
    errors: list[str] = []
    for language in sorted(locales - regions):
        errors.append(f"{project_path}: locale {language!r} is present in catalogs but missing from knownRegions")
    for language in sorted(regions - locales):
        errors.append(f"{project_path}: knownRegions locale {language!r} is missing from the catalogs")
    return errors


def required_languages(value: str, paths: list[Path]) -> list[str]:
    """Resolve the --require option into a stable, de-duplicated locale list."""
    if value.strip().lower() == "all":
        return discover_languages(paths)
    return sorted({language.strip() for language in value.split(",") if language.strip()})


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
                if lang == "zh-Hans":
                    errors.extend(
                        zh_hans_glossary_errors(path, key, expected_units[unit_path], value, unit_path)
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
        default="all",
        help=(
            "Comma-separated languages that must be fully translated, or 'all' to discover every locale "
            "across the catalogs (default: all)."
        ),
    )
    parser.add_argument(
        "--no-compile",
        action="store_true",
        help="Skip the optional xcstringstool compile step.",
    )
    parser.add_argument("catalogs", nargs="*", default=DEFAULT_CATALOGS)
    args = parser.parse_args()

    catalogs = args.catalogs or DEFAULT_CATALOGS
    catalog_paths = [Path(name) for name in catalogs]
    required = required_languages(args.require, catalog_paths)

    if not required:
        parser.error("--require must contain at least one locale or 'all'")

    all_errors: list[str] = []
    if catalogs == DEFAULT_CATALOGS:
        all_errors.extend(validate_project_languages(catalog_paths, DEFAULT_PROJECT_FILE))
        all_errors.extend(validate_swift_literal_coverage(DEFAULT_SWIFT_SOURCE_ROOT, catalog_paths[0]))
    for path in catalog_paths:
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
