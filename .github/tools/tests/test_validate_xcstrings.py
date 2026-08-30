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


class ZhHansGlossaryTests(unittest.TestCase):
    def errors(self, key: str, source: str, value: str) -> list[str]:
        return VALIDATOR.zh_hans_glossary_errors(Path("Localizable.xcstrings"), key, source, value, ())

    def test_redaction_forbids_zhezai_and_yinqu(self) -> None:
        self.assertTrue(self.errors("Redaction", "Redaction", "遮盖"))
        self.assertTrue(self.errors("Redact recognized sensitive data", "Redact recognized sensitive data", "隐去识别到的敏感数据"))
        self.assertEqual(self.errors("Redaction", "Redaction", "脱敏"), [])

    def test_certificate_pinning_forbids_suoding(self) -> None:
        source = "Certificate pinning still blocks interception"
        self.assertTrue(self.errors(source, source, "证书锁定仍在阻止拦截"))
        self.assertEqual(self.errors(source, source, "证书固定仍在阻止拦截"), [])

    def test_pin_ui_action_is_not_a_pinning_rule(self) -> None:
        # UI "pin"/"pinned" (not "pinning") legitimately uses 固定 and must not trip the rule.
        self.assertEqual(self.errors("No pinned requests", "No pinned requests", "无固定的请求"), [])
        source = "Unpin another Assistant conversation before pinning this one."
        self.assertEqual(self.errors(source, source, "置顶此助手对话前，请先取消置顶另一个对话。"), [])

    def test_named_compose_feature_forbids_bianxie(self) -> None:
        self.assertTrue(self.errors("Compose", "Compose", "编写"))
        self.assertEqual(self.errors("Compose", "Compose", "Compose"), [])
        # "user-authored filter text" has no "Compose" trigger, so 编写 is allowed.
        source = "%1$@ contains user-authored filter text."
        self.assertEqual(self.errors(source, source, "%1$@ 包含用户编写的过滤文本。"), [])

    def test_protobuf_wire_format_forbids_xianlu_geshi(self) -> None:
        source = "This frame does not look like a valid Protobuf wire-format payload."
        self.assertTrue(self.errors(source, source, "此帧看起来不是有效的 Protobuf 线路格式有效载荷。"))
        self.assertEqual(self.errors(source, source, "此帧看起来不是有效的 Protobuf 线格式有效载荷。"), [])

    def test_ai_model_token_forbids_lingpai(self) -> None:
        self.assertTrue(self.errors("Maximum output tokens", "Maximum output tokens", "最大输出令牌数"))
        self.assertEqual(self.errors("Maximum output tokens", "Maximum output tokens", "最大输出 token 数"), [])

    def test_status_code_requires_zhuangtaima(self) -> None:
        self.assertTrue(self.errors("Status code", "Status code", "代码"))
        self.assertEqual(self.errors("Status code", "Status code", "状态码"), [])

    def test_glossary_requires_the_preferred_term(self) -> None:
        self.assertTrue(self.errors("Redaction", "Redaction", "敏感信息处理"))
        self.assertTrue(self.errors("Compose", "Compose", "请求编辑器"))

    def test_auth_token_keeps_lingpai(self) -> None:
        # A pairing/auth token key is not in the AI set, so 令牌 stays valid.
        self.assertEqual(self.errors("Pairing token", "Pairing token", "配对令牌"), [])

    def test_validate_catalog_flags_mistranslated_zh_hans(self) -> None:
        catalog = {
            "sourceLanguage": "en",
            "strings": {
                "Redaction": {
                    "localizations": {
                        "zh-Hans": {"stringUnit": {"state": "translated", "value": "遮盖"}}
                    }
                }
            },
            "version": "1.0",
        }
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "Localizable.xcstrings"
            path.write_text(json.dumps(catalog), encoding="utf-8")
            errors = VALIDATOR.validate_catalog(path, ["zh-Hans"])
            self.assertTrue(any("redaction must use" in error for error in errors))

    def test_swift_literal_coverage_reports_missing_catalog_key(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source_root = root / "Rockxy"
            source_root.mkdir()
            (source_root / "Example.swift").write_text(
                'let value = String(localized: "Missing key", bundle: .main)\n',
                encoding="utf-8",
            )
            catalog = root / "Localizable.xcstrings"
            catalog.write_text(
                json.dumps({"sourceLanguage": "en", "strings": {}, "version": "1.0"}),
                encoding="utf-8",
            )

            errors = VALIDATOR.validate_swift_literal_coverage(source_root, catalog)

            self.assertTrue(any("Missing key" in error for error in errors))

    def test_swift_literal_coverage_accepts_catalogued_key(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source_root = root / "Rockxy"
            source_root.mkdir()
            (source_root / "Example.swift").write_text(
                'let value = String(localized: "Known key", bundle: .main)\n',
                encoding="utf-8",
            )
            catalog = root / "Localizable.xcstrings"
            catalog.write_text(
                json.dumps({"sourceLanguage": "en", "strings": {"Known key": {}}, "version": "1.0"}),
                encoding="utf-8",
            )

            self.assertEqual(VALIDATOR.validate_swift_literal_coverage(source_root, catalog), [])


if __name__ == "__main__":
    unittest.main()
