#!/usr/bin/env python3
"""Regression tests for the Build & Validate change classifier."""

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "classify_ci_changes.py"
SPEC = importlib.util.spec_from_file_location("classify_ci_changes", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("unable to load CI change classifier")
classifier = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(classifier)


class CIChangeClassifierTests(unittest.TestCase):
    def test_readmes_and_documentation_use_lightweight_ci(self):
        paths = [
            "README.md",
            "README.vi.md",
            "docs/getting-started/first-capture.mdx",
            "docs/images/WelcomeRockxy.png",
            "CONTRIBUTING.md",
            "legal/BINARY-EULA-v1.0.md",
        ]

        self.assertTrue(classifier.is_lightweight_only(paths))

    def test_release_metadata_uses_lightweight_ci(self):
        paths = [
            "CHANGELOG.md",
            "appcast.xml",
            "releases/catalog.json",
            "releases/latest.json",
        ]

        self.assertTrue(classifier.is_lightweight_only(paths))
        self.assertTrue(classifier.release_metadata_changed(paths))

    def test_empty_history_only_diff_uses_lightweight_ci(self):
        self.assertTrue(classifier.is_lightweight_only([]))
        self.assertFalse(classifier.release_metadata_changed([]))

    def test_source_change_requires_full_ci(self):
        self.assertFalse(
            classifier.is_lightweight_only(["Rockxy/Core/ProxyEngine/ProxyServer.swift"])
        )

    def test_mixed_documentation_and_source_requires_full_ci(self):
        self.assertFalse(
            classifier.is_lightweight_only(
                ["README.md", "RockxyTests/Core/ProxyEngine/ProxyServerTests.swift"]
            )
        )

    def test_mixed_source_and_release_metadata_still_requires_validation(self):
        paths = ["Rockxy/RockxyApp.swift", "releases/latest.json"]

        self.assertFalse(classifier.is_lightweight_only(paths))
        self.assertTrue(classifier.release_metadata_changed(paths))

    def test_workflow_change_requires_full_ci(self):
        self.assertFalse(
            classifier.is_lightweight_only([".github/workflows/build.yml"])
        )

    def test_null_delimited_paths_preserve_spaces(self):
        self.assertEqual(
            classifier.paths_from_null_delimited(
                b"docs/Release Notes.mdx\0README.md\0"
            ),
            ["docs/Release Notes.mdx", "README.md"],
        )


if __name__ == "__main__":
    unittest.main()
