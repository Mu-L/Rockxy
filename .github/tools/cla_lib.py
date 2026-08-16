#!/usr/bin/env python3
"""Pure, network-free logic for the Rockxy ICLA v2.0 contributor-license gate.

This module holds every decision the CLA gate makes so the behaviour can be unit
tested without a GitHub token or network access. The thin orchestration layer that
talks to the GitHub REST API lives in ``cla_gate.py`` and imports from here.

Design invariants:
- Fail closed. Ambiguity (unresolved commit author, invalid digest, malformed
  ledger) must never resolve to "covered".
- Evidence records are immutable and append-only. Serialization is deterministic
  so the signature ledger is diff-stable regardless of input ordering.
- ICLA v2.0 Section 10: acceptance covers the assent pull request plus every
  Contribution submitted afterward while the version is in effect. A signature
  from a *different, later* pull request never covers an *earlier-opened* one.
"""

from __future__ import annotations

import hashlib
import re
from datetime import datetime, timezone

# The exact assent statement a contributor must post to accept ICLA v2.0.
ASSENT_STATEMENT = "I have read and agree to the Rockxy ICLA v2.0"

ICLA_VERSION = "2.0"
DOCUMENT_PATH = "legal/cla/ICLA-v2.0.md"

# Identities excluded from the required-signer set. These are matched by *exact*
# GitHub numeric user ID and by *exact* login. We deliberately do not use a
# broad "ends with [bot]" heuristic: an unknown bot is treated as a required
# human and fails the gate closed until the Project Owner adds it here.
OWNER_IDENTITIES = frozenset({(9362970, "LocNguyenHuu")})
BOT_IDENTITIES = frozenset(
    {
        (49699333, "dependabot[bot]"),
        (41898282, "github-actions[bot]"),
        (29139614, "renovate[bot]"),
    }
)
WORKFLOW_BOT_USER_ID = 41898282

STATUS_CONTEXT = "Rockxy CLA"
COAUTHOR_PREFIX_RE = re.compile(r"^\s*Co-authored-by\s*:", re.IGNORECASE)
COAUTHOR_RE = re.compile(r"^\s*Co-authored-by\s*:\s*(.+?)\s*<([^<>\r\n]+)>\s*$", re.IGNORECASE)
GITHUB_NOREPLY_RE = re.compile(r"^(\d+)\+([^@]+)@users\.noreply\.github\.com$")


class LedgerConflictError(RuntimeError):
    """Raised when the signature ledger cannot be updated safely."""


def is_valid_sha256(value: str) -> bool:
    """Return True only for a canonical lowercase 64-character hex digest."""
    if not isinstance(value, str) or len(value) != 64:
        return False
    try:
        int(value, 16)
    except ValueError:
        return False
    return value == value.lower()


def compute_sha256(data: bytes) -> str:
    """Compute the lowercase hex SHA-256 of raw document bytes."""
    return hashlib.sha256(data).hexdigest()


def parse_expected_digest(sha256_file_text: str) -> str:
    """Extract the expected digest token from a ``shasum -a 256`` style file.

    The file format is ``<hex>  <path>``. Only the first whitespace-delimited
    token is used, normalized to lowercase. A non-hex token yields an empty
    string so callers fail closed.
    """
    stripped = sha256_file_text.strip()
    if not stripped:
        return ""
    token = stripped.split()[0].strip().lower()
    return token if is_valid_sha256(token) else ""


def verify_document_digest(document_bytes: bytes, expected_digest: str) -> tuple[bool, str]:
    """Verify the ICLA document against the pinned digest.

    Returns ``(ok, actual_digest)``. ``ok`` is True only when the expected digest
    is a valid SHA-256 and matches the freshly computed digest of the document.
    """
    actual = compute_sha256(document_bytes)
    ok = is_valid_sha256(expected_digest) and actual == expected_digest
    return ok, actual


def is_excluded_identity(user_id: int | None, login: str | None) -> bool:
    """Return True only for an exact Project Owner or known-bot identity pair."""
    if user_id is None or login is None:
        return False
    identity = (int(user_id), login)
    return identity in OWNER_IDENTITIES or identity in BOT_IDENTITIES


def merge_policy_preserves_commit_shas(repository: dict) -> bool:
    """The private coverage ledger requires original PR commits to remain reachable."""
    return (
        repository.get("allow_merge_commit") is True
        and repository.get("allow_squash_merge") is False
        and repository.get("allow_rebase_merge") is False
    )


def required_human_contributors(
    commits: list[dict],
    pull_author: dict | None = None,
) -> tuple[dict[int, str], list[str]]:
    """Reduce PR commits to the human authors whose acceptance is required.

    ``commits`` is the GitHub ``/pulls/{n}/commits`` payload shape: each element
    has a ``sha`` and an ``author`` that is either a GitHub user object (with
    ``id`` and ``login``) or ``None`` when the commit email is not linked to any
    GitHub account.

    Returns ``(required, unresolved)`` where ``required`` maps numeric user ID to
    login and ``unresolved`` lists commit shas whose human author could not be
    resolved to a GitHub account. Any non-empty ``unresolved`` must fail closed.
    """
    required: dict[int, str] = {}
    unresolved: list[str] = []
    if pull_author is not None:
        author_id = pull_author.get("id")
        author_login = pull_author.get("login", "")
        if author_id is None:
            unresolved.append("pull-request-author")
        elif not is_excluded_identity(author_id, author_login):
            required[int(author_id)] = author_login
    authors_by_commit, commit_unresolved = resolved_commit_contributors(commits)
    unresolved.extend(commit_unresolved)
    for authors in authors_by_commit.values():
        for author in authors:
            user_id = author["userId"]
            login = author["login"]
            if is_excluded_identity(user_id, login):
                continue
            required[user_id] = login
    return required, unresolved


def resolved_commit_contributors(commits: list[dict]) -> tuple[dict[str, list[dict]], list[str]]:
    """Resolve primary authors and Co-authored-by trailers to stable GitHub identities."""
    by_email: dict[str, dict] = {}
    authors_by_commit: dict[str, list[dict]] = {}
    unresolved: list[str] = []
    for commit in commits:
        sha = commit.get("sha", "")
        author = commit.get("author")
        if not isinstance(author, dict) or author.get("id") is None or not author.get("login"):
            unresolved.append(sha)
            continue
        identity = {"userId": int(author["id"]), "login": author["login"]}
        authors_by_commit.setdefault(sha, []).append(identity)
        email = commit.get("commit", {}).get("author", {}).get("email")
        if isinstance(email, str) and email:
            by_email[email.casefold()] = identity

    for commit in commits:
        sha = commit.get("sha", "")
        message = commit.get("commit", {}).get("message", "")
        if not isinstance(message, str):
            continue
        for line in message.splitlines():
            if not COAUTHOR_PREFIX_RE.match(line):
                continue
            match = COAUTHOR_RE.match(line)
            if match is None:
                unresolved.append(f"{sha}:malformed-coauthor")
                continue
            email = match.group(2).strip()
            identity = by_email.get(email.casefold())
            if identity is None:
                noreply = GITHUB_NOREPLY_RE.fullmatch(email)
                if noreply is not None:
                    identity = {"userId": int(noreply.group(1)), "login": noreply.group(2)}
            if identity is None:
                unresolved.append(f"{sha}:unresolved-coauthor:{email}")
                continue
            existing = authors_by_commit.setdefault(sha, [])
            if identity not in existing:
                existing.append(identity)
    return authors_by_commit, unresolved


def parse_github_timestamp(value: str) -> datetime:
    """Parse a GitHub ISO-8601 UTC timestamp (``...Z``) into an aware datetime."""
    if not isinstance(value, str) or not value:
        raise ValueError("empty timestamp")
    normalized = value.strip()
    if normalized.endswith("Z"):
        normalized = normalized[:-1] + "+00:00"
    parsed = datetime.fromisoformat(normalized)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


def is_contribution_covered(
    user_records: list[dict],
    target_pr_number: int,
    target_pr_created_at: str,
    expected_document_sha256: str,
) -> bool:
    """Decide whether one contributor's Contribution in a PR is covered.

    Models ICLA v2.0 Section 10:
    - Same-PR assent: a signature whose ``prNumber`` equals the target PR always
      covers that PR (the assent was posted in it).
    - Later Contribution: a signature covers a target PR opened at or after the
      acceptance timestamp.

    A signature from a different, later PR does not cover an earlier-opened PR:
    such a target is neither the assent PR nor opened after acceptance.
    """
    target_opened = parse_github_timestamp(target_pr_created_at)
    for record in user_records:
        if record.get("iclaVersion") != ICLA_VERSION:
            continue
        if record.get("documentSha256") != expected_document_sha256:
            continue
        if record.get("prNumber") == target_pr_number:
            return True
        accepted_at = record.get("acceptedAt")
        if not accepted_at:
            continue
        if target_opened >= parse_github_timestamp(accepted_at):
            return True
    return False


def group_records_by_user(records: list[dict]) -> dict[int, list[dict]]:
    grouped: dict[int, list[dict]] = {}
    for record in records:
        user_id = record.get("userId")
        if user_id is None:
            continue
        grouped.setdefault(int(user_id), []).append(record)
    return grouped


def evaluate_missing_signers(
    records: list[dict],
    required: dict[int, str],
    target_pr_number: int,
    target_pr_created_at: str,
    expected_document_sha256: str,
) -> dict[int, str]:
    """Return the subset of required contributors not yet covered for this PR."""
    grouped = group_records_by_user(records)
    missing: dict[int, str] = {}
    for user_id, login in required.items():
        user_records = grouped.get(user_id, [])
        if not is_contribution_covered(
            user_records,
            target_pr_number,
            target_pr_created_at,
            expected_document_sha256,
        ):
            missing[user_id] = login
    return missing


def make_record(
    *,
    repository_id: int,
    login: str,
    user_id: int,
    pr_number: int,
    pr_id: int,
    pr_node_id: str,
    comment_id: int,
    accepted_at: str,
    document_sha256: str,
    document_commit: str,
    document_url: str,
) -> dict:
    """Build one immutable evidence record for the signature ledger."""
    return {
        "repositoryId": int(repository_id),
        "login": login,
        "userId": int(user_id),
        "prNumber": int(pr_number),
        "prId": int(pr_id),
        "prNodeId": pr_node_id,
        "commentId": int(comment_id),
        "acceptedAt": accepted_at,
        "assentStatement": ASSENT_STATEMENT,
        "iclaVersion": ICLA_VERSION,
        "documentSha256": document_sha256,
        "documentCommit": document_commit,
        "documentUrl": document_url,
    }


def new_ledger() -> dict:
    return {"iclaVersion": ICLA_VERSION, "records": [], "coveredPullRequests": []}


def make_covered_pull_record(
    *,
    repository_id: int,
    pull: dict,
    commits: list[dict],
    required: dict[int, str],
) -> dict:
    """Build immutable proof that one exact PR head passed the ICLA gate."""
    authors_by_commit, unresolved = resolved_commit_contributors(commits)
    if unresolved:
        raise ValueError("cannot record a covered pull with unresolved commit contributors")
    commit_records = [
        {"sha": sha, "userId": author["userId"], "login": author["login"]}
        for sha, authors in authors_by_commit.items()
        for author in authors
    ]
    return {
        "repositoryId": int(repository_id),
        "prNumber": int(pull["number"]),
        "prId": int(pull["id"]),
        "prNodeId": pull["node_id"],
        "pullCreatedAt": pull["created_at"],
        "headSha": pull["head"]["sha"],
        "contributors": [
            {"userId": user_id, "login": login}
            for user_id, login in sorted(required.items())
        ],
        "commits": sorted(commit_records, key=lambda record: (record["sha"], record["userId"])),
    }


def validate_covered_pull_record(record: dict) -> None:
    if not isinstance(record, dict):
        raise ValueError("covered pull record is not an object")
    for field in ("repositoryId", "prNumber", "prId"):
        value = record.get(field)
        if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
            raise ValueError(f"covered pull record {field} must be a positive integer")
    for field in ("prNodeId", "pullCreatedAt", "headSha"):
        value = record.get(field)
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"covered pull record {field} must be a non-empty string")
    parse_github_timestamp(record["pullCreatedAt"])
    if len(record["headSha"]) != 40 or any(c not in "0123456789abcdef" for c in record["headSha"]):
        raise ValueError("covered pull record headSha is not a full lowercase Git SHA-1")
    contributors = record.get("contributors")
    commits = record.get("commits")
    if not isinstance(contributors, list) or not isinstance(commits, list) or not commits:
        raise ValueError("covered pull record contributors/commits are invalid")
    for contributor in contributors:
        if not isinstance(contributor, dict):
            raise ValueError("covered pull contributor is not an object")
        if not isinstance(contributor.get("userId"), int) or contributor["userId"] <= 0:
            raise ValueError("covered pull contributor userId must be positive")
        if not isinstance(contributor.get("login"), str) or not contributor["login"]:
            raise ValueError("covered pull contributor login is invalid")
    for commit in commits:
        if not isinstance(commit, dict):
            raise ValueError("covered pull commit is not an object")
        sha = commit.get("sha")
        if not isinstance(sha, str) or len(sha) != 40 or any(c not in "0123456789abcdef" for c in sha):
            raise ValueError("covered pull commit sha is invalid")
        if not isinstance(commit.get("userId"), int) or commit["userId"] <= 0:
            raise ValueError("covered pull commit userId must be positive")
        if not isinstance(commit.get("login"), str) or not commit["login"]:
            raise ValueError("covered pull commit login is invalid")


def validate_record(record: dict) -> None:
    if not isinstance(record, dict):
        raise ValueError("ledger record is not an object")
    for field in ("repositoryId", "userId", "prNumber", "prId", "commentId"):
        value = record.get(field)
        if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
            raise ValueError(f"ledger record {field} must be a positive integer")
    for field in ("login", "prNodeId", "acceptedAt", "documentUrl"):
        value = record.get(field)
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"ledger record {field} must be a non-empty string")
    parse_github_timestamp(record["acceptedAt"])
    if record.get("iclaVersion") != ICLA_VERSION:
        raise ValueError("ledger record has an unexpected ICLA version")
    if record.get("assentStatement") != ASSENT_STATEMENT:
        raise ValueError("ledger record does not contain the exact assent statement")
    digest = record.get("documentSha256")
    if not is_valid_sha256(digest):
        raise ValueError("ledger record documentSha256 is invalid")
    document_commit = record.get("documentCommit")
    if (
        not isinstance(document_commit, str)
        or len(document_commit) != 40
        or any(character not in "0123456789abcdef" for character in document_commit)
    ):
        raise ValueError("ledger record documentCommit is not a full lowercase Git SHA-1")
    expected_suffix = f"/blob/{document_commit}/{DOCUMENT_PATH}"
    if not record["documentUrl"].endswith(expected_suffix):
        raise ValueError("ledger record documentUrl is not pinned to documentCommit")


def load_ledger(text: str) -> dict:
    """Parse a ledger JSON document, tolerating an empty file and the empty
    ``{"signedContributors": []}`` bootstrap shape kept on the default branch."""
    import json

    if not text or not text.strip():
        return new_ledger()
    data = json.loads(text)
    if not isinstance(data, dict):
        raise ValueError("ledger root is not an object")
    records = data.get("records")
    if records is None and isinstance(data.get("signedContributors"), list):
        # Bootstrap store shape carried on the default branch; treat as empty.
        records = [] if not data["signedContributors"] else data["signedContributors"]
    if records is None:
        records = []
    if not isinstance(records, list):
        raise ValueError("ledger records is not a list")
    for record in records:
        validate_record(record)
    covered_pulls = data.get("coveredPullRequests", [])
    if not isinstance(covered_pulls, list):
        raise ValueError("ledger coveredPullRequests is not a list")
    for record in covered_pulls:
        validate_covered_pull_record(record)
    version = data.get("iclaVersion", ICLA_VERSION)
    if version != ICLA_VERSION:
        raise ValueError(f"unexpected ledger ICLA version: {version!r}")
    return {"iclaVersion": version, "records": records, "coveredPullRequests": covered_pulls}


def _record_sort_key(record: dict) -> tuple:
    return (
        int(record.get("userId", 0)),
        int(record.get("prNumber", 0)),
        int(record.get("commentId", 0)),
        str(record.get("acceptedAt", "")),
    )


def record_exists(records: list[dict], comment_id: int) -> bool:
    """A GitHub comment can assent at most once; dedup by its numeric ID."""
    return any(int(r.get("commentId", -1)) == int(comment_id) for r in records)


def append_record(ledger: dict, record: dict) -> dict:
    """Return a new ledger with ``record`` appended if its comment is not already
    present. The record list is kept sorted for deterministic serialization."""
    records = list(ledger.get("records", []))
    if not record_exists(records, record["commentId"]):
        records.append(record)
    records = sorted(records, key=_record_sort_key)
    return {
        "iclaVersion": ledger.get("iclaVersion", ICLA_VERSION),
        "records": records,
        "coveredPullRequests": list(ledger.get("coveredPullRequests", [])),
    }


def append_covered_pull_record(ledger: dict, record: dict) -> dict:
    """Append one exact successful PR-head record, idempotently."""
    covered = list(ledger.get("coveredPullRequests", []))
    key = (record["repositoryId"], record["prId"], record["headSha"])
    if not any((item["repositoryId"], item["prId"], item["headSha"]) == key for item in covered):
        covered.append(record)
    covered.sort(key=lambda item: (item["repositoryId"], item["prNumber"], item["headSha"]))
    return {
        "iclaVersion": ledger.get("iclaVersion", ICLA_VERSION),
        "records": list(ledger.get("records", [])),
        "coveredPullRequests": covered,
    }


def serialize_ledger(ledger: dict) -> str:
    """Deterministically serialize the ledger: sorted records, sorted keys, and a
    trailing newline so re-runs produce byte-identical output."""
    import json

    normalized = {
        "iclaVersion": ledger.get("iclaVersion", ICLA_VERSION),
        "records": sorted(ledger.get("records", []), key=_record_sort_key),
        "coveredPullRequests": sorted(
            ledger.get("coveredPullRequests", []),
            key=lambda item: (item["repositoryId"], item["prNumber"], item["headSha"]),
        ),
    }
    return json.dumps(normalized, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
