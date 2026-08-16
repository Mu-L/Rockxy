# Release provenance

Rockxy release metadata identifies the exact signed binary artifact and, for
new releases using schema version 2, the related public source edition.

The provenance record intentionally distinguishes these artifacts:

- `checksum_sha256`, `dmg_length`, and `sparkle_ed_signature` identify and
  authenticate the official DMG;
- `binary_license` identifies the terms for that official binary;
- `public_source_commit` identifies the exact public AGPL source snapshot
  imported into the downstream release build;
- `source_relationship` is `separate-source-edition`, because that public
  commit is not represented as the official DMG's complete or exact build
  source; and
- `third_party_notices_url` points to the notice file uploaded with that
  official release, and `third_party_notices_sha256` identifies those exact
  bytes.

`latest.json` uses camel-case aliases for these fields. `catalog.json` keeps
older signed releases as historical schema-version-1 entries when the exact
public source commit was not previously recorded; the newest release written
under schema version 2 carries the complete provenance record.

The canonical licensing boundary is documented in [LICENSING.md](../LICENSING.md).
