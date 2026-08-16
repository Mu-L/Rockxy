#!/usr/bin/env python3
"""Regression tests for release provenance validation."""

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "validate_metadata.py"
SPEC = importlib.util.spec_from_file_location("validate_metadata", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("unable to load release metadata validator")
validator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validator)


class ProvenanceTests(unittest.TestCase):
    def complete_record(self) -> dict:
        commit = "a" * 40
        return {
            "release_tag": "v1.2.3",
            "binary_license": "Rockxy Binary EULA v1.0",
            "binary_license_url": (
                "https://github.com/RockxyApp/Rockxy/blob/"
                f"{commit}/legal/BINARY-EULA-v1.0.md"
            ),
            "community_mode_available_without_purchase": True,
            "public_source_edition_url": "https://github.com/RockxyApp/Rockxy",
            "public_source_edition_license": "AGPL-3.0-or-later",
            "public_source_commit": commit,
            "public_source_commit_url": f"https://github.com/RockxyApp/Rockxy/tree/{commit}",
            "source_relationship": "separate-source-edition",
            "third_party_notices_url": (
                "https://github.com/RockxyApp/Rockxy/releases/download/"
                "v1.2.3/THIRD_PARTY_NOTICES.txt"
            ),
            "third_party_notices_sha256": "b" * 64,
            "terms_url": "https://rockxy.io/legal/archive/terms-2026-08-14.html",
            "terms_version": "2026-08-14",
            "terms_sha256": "c" * 64,
            "privacy_notice_url": "https://rockxy.io/legal/archive/privacy-2026-08-14.html",
            "privacy_notice_version": "2026-08-14",
            "privacy_notice_sha256": "d" * 64,
        }

    def test_schema_v2_fails_when_provenance_is_entirely_absent(self):
        with self.assertRaisesRegex(SystemExit, "missing required distribution provenance"):
            validator.validate_distribution_provenance(
                Path("catalog.json"),
                {},
                validator.CATALOG_PROVENANCE_REQUIRED,
                snake_case=True,
                require_all=True,
            )

    def test_notice_url_must_match_release_tag(self):
        record = self.complete_record()
        record["third_party_notices_url"] = record["third_party_notices_url"].replace(
            "v1.2.3", "v9.9.9"
        )
        with self.assertRaisesRegex(SystemExit, "third-party notices URL"):
            validator.validate_distribution_provenance(
                Path("catalog.json"),
                record,
                validator.CATALOG_PROVENANCE_REQUIRED,
                snake_case=True,
                require_all=True,
            )

    def test_complete_schema_v2_provenance_passes(self):
        validator.validate_distribution_provenance(
            Path("catalog.json"),
            self.complete_record(),
            validator.CATALOG_PROVENANCE_REQUIRED,
            snake_case=True,
            require_all=True,
        )


if __name__ == "__main__":
    unittest.main()
