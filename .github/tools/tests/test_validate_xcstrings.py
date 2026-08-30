import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


VALIDATOR_PATH = Path(__file__).resolve().parents[1] / "validate_xcstrings.py"
SPEC = importlib.util.spec_from_file_location("validate_xcstrings", VALIDATOR_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Cannot load validator from {VALIDATOR_PATH}")
VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)


def catalog_with(localizations: dict[str, str]) -> dict:
    return {
        "sourceLanguage": "en",
        "strings": {
            "Start Proxy": {
                "localizations": {
                    language: {"stringUnit": {"state": "translated", "value": value}}
                    for language, value in localizations.items()
                }
            }
        },
        "version": "1.0",
    }


class LanguageDiscoveryTests(unittest.TestCase):
    def write_catalog(self, directory: Path, name: str, localizations: dict[str, str]) -> Path:
        path = directory / name
        path.write_text(json.dumps(catalog_with(localizations)), encoding="utf-8")
        return path

    def test_discovers_union_of_locales_and_keeps_shipped_baseline(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            app = self.write_catalog(root, "Localizable.xcstrings", {"de": "Proxy starten"})
            info = self.write_catalog(root, "InfoPlist.xcstrings", {"fr": "Demarrer le proxy"})

            self.assertEqual(VALIDATOR.discover_languages([app, info]), ["de", "fr", "zh-Hans"])

    def test_union_requires_new_locale_in_every_catalog(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            app = self.write_catalog(
                root,
                "Localizable.xcstrings",
                {"de": "Proxy starten", "zh-Hans": "Start Proxy"},
            )
            info = self.write_catalog(root, "InfoPlist.xcstrings", {"zh-Hans": "Start Proxy"})

            required = VALIDATOR.required_languages("all", [app, info])
            errors = VALIDATOR.validate_catalog(info, required)

            self.assertTrue(any("missing de translation" in error for error in errors))

    def test_explicit_locale_list_is_trimmed_sorted_and_deduplicated(self) -> None:
        self.assertEqual(VALIDATOR.required_languages(" de,zh-Hans,de ", []), ["de", "zh-Hans"])

    def test_reads_quoted_and_unquoted_project_regions(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            project = Path(temporary_directory) / "project.pbxproj"
            project.write_text(
                'knownRegions = (\n en,\n Base,\n de,\n "pt-BR",\n);\n',
                encoding="utf-8",
            )

            self.assertEqual(VALIDATOR.project_languages(project), ["de", "pt-BR"])

    def test_reports_catalog_and_project_locale_mismatches(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            catalog = self.write_catalog(root, "Localizable.xcstrings", {"de": "Proxy starten"})
            project = root / "project.pbxproj"
            project.write_text('knownRegions = (\n en,\n Base,\n fr,\n);\n', encoding="utf-8")

            errors = VALIDATOR.validate_project_languages([catalog], project)

            self.assertTrue(any("'de' is present in catalogs" in error for error in errors))
            self.assertTrue(any("'fr' is missing from the catalogs" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
