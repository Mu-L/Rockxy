# Rockxy Contributor Agreement Policy

## Current agreements

- Individual contributors: [ICLA v2.0](ICLA-v2.0.md)
- Organizations that own or control Contributions:
  [CCLA v1.0](CCLA-v1.0.md) plus an ICLA from each contributor
- Record privacy: [CLA-PRIVACY.md](CLA-PRIVACY.md)

The ICLA is a broad license, not a copyright assignment. Contributors retain
their copyright. The Project Owner receives transferable and sublicensable
rights needed for the public AGPL source edition and separately licensed
official Rockxy distributions. Contributions incorporated into the public
source edition remain available there under its public source license.

## Version and acceptance policy

The ICLA v2.0 document path is immutable. A material change requires a new
versioned document and a new signature store. Acceptance of one version never
counts as acceptance of a later version.

For ICLA v2.0, the exact GitHub acceptance statement is:

> I have read and agree to the Rockxy ICLA v2.0

The version-specific signature store path is `signatures/icla-v2.0.json`. On the
default branch it is an empty example store; live acceptance records are written
to the same path on the dedicated **`cla-signatures`** branch (never on
protected `main`/`develop`). Each record must be read together with the
versioned document, the signature comment, the recorded document SHA-256, and
the immutable Git commit containing those exact document bytes. The document’s
SHA-256 is stored in `ICLA-v2.0.sha256` and recomputed and checked by the CLA
gate on every run; a mismatch disables acceptance and marks the `Rockxy CLA`
status red.

The gate is a repository-owned Python script (`.github/tools/cla_gate.py`,
logic in `cla_lib.py`) run by the `Rockxy CLA` workflow. It does not depend on
any third-party CLA action, and under `pull_request_target` it never checks out
or executes pull request head (fork) code — only the trusted default-branch gate
code at a pinned `actions/checkout` commit. It excludes only the exact Project
Owner and exact known-bot identities (by numeric ID and login) and fails closed
for any commit author it cannot resolve to a GitHub account.

The workflow also requires the repository variable
`ROCKXY_LEGAL_IDENTITY_CONFIRMED=true`. The Project Owner confirmed the legal
name **Nguyen Huu Loc**, GitHub account `LocNguyenHuu`, and public English name
**Stephen** on 2026-08-14. Enable the gate only after the identity-bearing ICLA,
CCLA, Binary EULA, privacy-controller notice, and recorded ICLA digest are all
present on the protected default branch. No ICLA v2.0 signature should be
accepted from a branch or document state that predates that update.

## Historical records

The former agreement is archived byte-for-byte at
`archive/CLA-v1.md`. Its existing records remain in
`signatures/cla.json`. They prove assent only to that historical agreement.
They must not be migrated, rewritten, or treated as ICLA v2.0 signatures.

## Organizational contributions

An employee must determine whether an employer owns or controls the proposed
Contribution. When it does, an authorized representative must execute the CCLA
and identify the authorized contributors. The executed CCLA and its changes are
kept privately by the Project Owner; the public repository should record only a
non-sensitive reference needed for merge review.

## Legal review note

These agreements are project-maintained legal drafts based on established CLA
structures. They have not been represented as advice from Rockxy’s attorney.
Before relying on them for a material transaction, company formation, or a
disputed contribution, the Project Owner should obtain advice for the relevant
jurisdiction and confirm the public contracting identity.
