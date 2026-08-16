# Contributor Agreement Signature Records

- `cla.json` is the preserved historical signature store for the archived v1
  agreement. Do not edit, migrate, or interpret it as acceptance of v2.
- `icla-v2.0.json` on the default branch is an **empty example store**. Live
  ICLA v2.0 acceptance records are written by the `Rockxy CLA` workflow to the
  same path on the dedicated **`cla-signatures`** branch, never on protected
  `main`/`develop`. The workflow bootstraps that branch from the default branch
  the first time it needs to record an acceptance.

## Evidence record schema (ICLA v2.0)

Each acceptance record in `signatures/icla-v2.0.json` on `cla-signatures`
contains:

| Field | Meaning |
| --- | --- |
| `repositoryId` | Stable numeric GitHub repository ID |
| `login` | GitHub login of the accepting contributor |
| `userId` | GitHub numeric user ID (the stable identity key) |
| `prNumber` | Pull request the assent was posted in |
| `prId` / `prNodeId` | Stable GitHub pull request ID and node ID |
| `commentId` | Numeric ID of the acceptance comment |
| `acceptedAt` | Acceptance timestamp reported by GitHub |
| `assentStatement` | Exact acceptance statement recorded by the gate |
| `iclaVersion` | Agreement version (`2.0`) |
| `documentSha256` | Exact SHA-256 of the accepted ICLA document |
| `documentCommit` | Immutable Git commit containing the accepted document |
| `documentUrl` | Immutable commit-pinned URL for the accepted document |

The workflow treats records as append-only and serializes them deterministically
(sorted, stable keys) so the ledger is diff-stable. A GitHub comment can assent
at most once; records are deduplicated by `commentId`. Repository administrators
can still rewrite an unprotected Git branch, so the Project Owner must preserve
an independent export of the branch before relying on it for a release or legal
transaction.

After an exact pull-request head passes the gate, the workflow also appends a
`coveredPullRequests` record containing the stable repository and pull-request
IDs, pull creation time, head SHA, resolved contributors, and exact commit SHAs.
The private release gate matches commercial-use evidence against both the
acceptance record and this successful-coverage record; manually shaped evidence
alone is not sufficient.

## Coverage and the `Rockxy CLA` status

Acceptance follows ICLA v2.0 Section 10: a signature covers the pull request it
was posted in, plus every Contribution submitted *afterward* while v2.0 is in
effect. A signature from a different, later pull request does **not** cover an
earlier-opened one. The gate sets a stable `Rockxy CLA` commit status on the PR
head SHA — success only when every required human contributor is covered,
otherwise pending (awaiting acceptance) or failure (unresolved commit author or
document-digest mismatch).

The gate also fails closed unless repository settings allow merge commits and
disable squash/rebase merges. This keeps the exact PR commit SHAs recorded in
`coveredPullRequests` reachable after merge for the downstream release audit.

Each record must remain attributable to its GitHub acceptance comment and pull
request. A future agreement version requires a new versioned document and a new
signature store; signatures are never silently carried forward.
