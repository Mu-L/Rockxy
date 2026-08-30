<!-- Please target the `develop` branch for all pull requests. -->

## Description
<!-- What does this PR do? Why is this change needed? -->

## Changes
<!-- List the key changes in this PR. -->

-
-

## Localization (if applicable)
<!-- For translation work, include the language/locale, affected screen or catalog key, and why the proposed wording is better. A screenshot or terminology reference is useful when relevant. Write "Not applicable" for non-localization PRs. -->

- Language / locale:
- Affected UI or catalog key:
- Verification / rationale:

## Checklist

<!-- Mark non-applicable items in the PR description. Translation-only PRs do not need Swift tests, lint, formatting, or a changelog entry unless Swift code, English source strings, or product behavior also changed. -->

- [ ] Tests added or updated
- [ ] `CHANGELOG.md` updated under `[Unreleased]` (skip for unreleased-only fixes)
- [ ] Docs updated in `docs/` if the change affects user-facing behavior
- [ ] User-facing strings localized with `String(localized:)`
- [ ] If string catalogs changed: placeholders and non-translatable technical details are unchanged
- [ ] If string catalogs changed: `python3 .github/tools/validate_xcstrings.py` passes (see `docs/development/localization.mdx`)
- [ ] No SwiftLint / SwiftFormat violations (`swiftlint lint --strict && swiftformat .`)
- [ ] If this PR touches helper packaging, release scripts, or platform compatibility claims, Intel + Apple Silicon validation was updated or re-run

## CLA

This project requires acceptance of the
[Individual Contributor License Agreement v2.0](../legal/cla/ICLA-v2.0.md).
The `Rockxy CLA` check will comment with the exact acceptance statement. You
must accept that version before your PR can be merged. If an employer or
another organization owns or controls the contribution, contact
`rockxyapp@gmail.com` about the CCLA first.
