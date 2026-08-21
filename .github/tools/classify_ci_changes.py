#!/usr/bin/env python3
"""Classify whether a change can use Rockxy's lightweight CI path."""

from __future__ import annotations

import sys
from pathlib import PurePosixPath
from typing import Iterable


LIGHTWEIGHT_FILES = {
    "LICENSE",
    "appcast.xml",
    "releases/catalog.json",
    "releases/latest.json",
}
DOCUMENTATION_SUFFIXES = {".md", ".mdx"}
DOCUMENTATION_DIRECTORIES = {"docs", "legal"}


def is_lightweight_path(path: str) -> bool:
    """Return whether *path* cannot affect application behavior or CI execution."""
    normalized = PurePosixPath(path)
    if path in LIGHTWEIGHT_FILES:
        return True
    if normalized.suffix.lower() in DOCUMENTATION_SUFFIXES:
        return True
    return bool(normalized.parts) and normalized.parts[0] in DOCUMENTATION_DIRECTORIES


def is_lightweight_only(paths: Iterable[str]) -> bool:
    """Return true when every changed path is documentation or release metadata.

    An empty diff is safe for the lightweight path. This occurs for history-only
    merges whose resulting tree is unchanged.
    """
    return all(is_lightweight_path(path) for path in paths)


def paths_from_null_delimited(payload: bytes) -> list[str]:
    """Decode the null-delimited output produced by ``git diff -z``."""
    return [
        path.decode("utf-8", errors="surrogateescape")
        for path in payload.split(b"\0")
        if path
    ]


def main() -> None:
    paths = paths_from_null_delimited(sys.stdin.buffer.read())
    print("true" if is_lightweight_only(paths) else "false")


if __name__ == "__main__":
    main()
