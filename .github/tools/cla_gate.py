#!/usr/bin/env python3
"""Rockxy ICLA v2.0 contributor-license gate.

Repository-owned replacement for third-party CLA actions. Runs from the trusted
default-branch checkout under ``pull_request_target`` / ``issue_comment`` and
never checks out or executes fork code. All GitHub interaction goes through the
REST API with the workflow token; every decision lives in ``cla_lib`` so it is
unit-testable without a network.

Behaviour:
1. Verify the ICLA document on disk against the pinned SHA-256; mismatch fails
   closed with a red ``Rockxy CLA`` status.
2. On an assent comment from a human contributor of the PR, append an immutable
   evidence record to ``signatures/icla-v2.0.json`` on the dedicated
   ``cla-signatures`` branch (bootstrapping the branch from the default branch if
   needed, and failing closed on update conflicts).
3. Evaluate every required human contributor's coverage, set the ``Rockxy CLA``
   commit status on the PR head SHA, and keep exactly one contributor-facing
   comment updated in place (no comment spam).
"""

from __future__ import annotations

import base64
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

import cla_lib as lib

SIGNATURES_PATH = "signatures/icla-v2.0.json"
COMMENT_MARKER = "<!-- rockxy-cla-gate -->"
SIGNATURES_BRANCH = os.environ.get("ROCKXY_CLA_SIGNATURES_BRANCH", "cla-signatures")
DOCUMENT_LOCAL_PATH = "legal/cla/ICLA-v2.0.md"
DIGEST_LOCAL_PATH = "legal/cla/ICLA-v2.0.sha256"
MAX_LEDGER_WRITE_ATTEMPTS = 3


class GitHubClient:
    def __init__(self, token: str, repo: str, api_url: str) -> None:
        self._token = token
        self._repo = repo
        self._api_url = api_url.rstrip("/")

    def _request(self, method: str, path: str, payload: dict | None = None) -> tuple[int, dict | list | None]:
        url = path if path.startswith("http") else f"{self._api_url}{path}"
        data = json.dumps(payload).encode("utf-8") if payload is not None else None
        request = urllib.request.Request(url, data=data, method=method)
        request.add_header("Authorization", f"Bearer {self._token}")
        request.add_header("Accept", "application/vnd.github+json")
        request.add_header("X-GitHub-Api-Version", "2022-11-28")
        request.add_header("User-Agent", "rockxy-cla-gate")
        if data is not None:
            request.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(request) as response:
                body = response.read()
                parsed = json.loads(body) if body else None
                return response.status, parsed
        except urllib.error.HTTPError as error:
            body = error.read()
            try:
                parsed = json.loads(body) if body else None
            except json.JSONDecodeError:
                parsed = None
            return error.code, parsed

    def get_pull(self, number: int) -> dict:
        status, data = self._request("GET", f"/repos/{self._repo}/pulls/{number}")
        if status != 200 or not isinstance(data, dict):
            raise RuntimeError(f"failed to fetch pull #{number}: HTTP {status}")
        return data

    def get_repository(self) -> dict:
        status, data = self._request("GET", f"/repos/{self._repo}")
        if status != 200 or not isinstance(data, dict):
            raise RuntimeError(f"failed to fetch repository settings: HTTP {status}")
        return data

    def list_pull_commits(self, number: int) -> list[dict]:
        commits: list[dict] = []
        page = 1
        while True:
            status, data = self._request(
                "GET", f"/repos/{self._repo}/pulls/{number}/commits?per_page=100&page={page}"
            )
            if status != 200 or not isinstance(data, list):
                raise RuntimeError(f"failed to list commits for pull #{number}: HTTP {status}")
            commits.extend(data)
            if len(data) < 100:
                break
            page += 1
        return commits

    def set_status(self, sha: str, state: str, description: str, target_url: str | None = None) -> None:
        payload = {
            "state": state,
            "context": lib.STATUS_CONTEXT,
            "description": description[:140],
        }
        if target_url:
            payload["target_url"] = target_url
        status, _ = self._request("POST", f"/repos/{self._repo}/statuses/{sha}", payload)
        if status not in (200, 201):
            raise RuntimeError(f"failed to set commit status on {sha}: HTTP {status}")

    def find_marker_comment(self, issue_number: int) -> dict | None:
        page = 1
        while True:
            status, data = self._request(
                "GET", f"/repos/{self._repo}/issues/{issue_number}/comments?per_page=100&page={page}"
            )
            if status != 200 or not isinstance(data, list):
                raise RuntimeError(f"failed to list comments for #{issue_number}: HTTP {status}")
            for comment in data:
                if (
                    comment.get("user", {}).get("id") == lib.WORKFLOW_BOT_USER_ID
                    and COMMENT_MARKER in (comment.get("body") or "")
                ):
                    return comment
            if len(data) < 100:
                return None
            page += 1

    def upsert_comment(self, issue_number: int, body: str) -> None:
        existing = self.find_marker_comment(issue_number)
        if existing is not None:
            if (existing.get("body") or "") == body:
                return
            status, _ = self._request(
                "PATCH", f"/repos/{self._repo}/issues/comments/{existing['id']}", {"body": body}
            )
            if status != 200:
                raise RuntimeError(f"failed to update gate comment: HTTP {status}")
            return
        status, _ = self._request(
            "POST", f"/repos/{self._repo}/issues/{issue_number}/comments", {"body": body}
        )
        if status not in (200, 201):
            raise RuntimeError(f"failed to post gate comment: HTTP {status}")

    def get_default_branch_head_sha(self, default_branch: str) -> str:
        status, data = self._request("GET", f"/repos/{self._repo}/git/ref/heads/{default_branch}")
        if status != 200 or not isinstance(data, dict):
            raise RuntimeError(f"failed to read default branch ref: HTTP {status}")
        return data["object"]["sha"]

    def ensure_branch(self, branch: str, default_branch: str) -> None:
        status, _ = self._request("GET", f"/repos/{self._repo}/git/ref/heads/{branch}")
        if status == 200:
            return
        if status != 404:
            raise RuntimeError(f"failed to probe branch {branch}: HTTP {status}")
        base_sha = self.get_default_branch_head_sha(default_branch)
        create_status, _ = self._request(
            "POST",
            f"/repos/{self._repo}/git/refs",
            {"ref": f"refs/heads/{branch}", "sha": base_sha},
        )
        if create_status not in (200, 201):
            raise RuntimeError(f"failed to bootstrap branch {branch}: HTTP {create_status}")

    def get_file(self, path: str, branch: str) -> tuple[str | None, str]:
        status, data = self._request(
            "GET", f"/repos/{self._repo}/contents/{path}?ref={branch}"
        )
        if status == 404:
            return None, ""
        if status != 200 or not isinstance(data, dict):
            raise RuntimeError(f"failed to read {path}@{branch}: HTTP {status}")
        encoded_content = data.get("content")
        if data.get("encoding") != "base64" or not isinstance(encoded_content, str) or not encoded_content:
            raise RuntimeError(
                f"failed to read {path}@{branch}: GitHub did not return non-empty base64 content"
            )
        try:
            compact_content = "".join(encoded_content.split())
            content = base64.b64decode(compact_content, validate=True).decode("utf-8")
        except (ValueError, UnicodeDecodeError) as error:
            raise RuntimeError(f"failed to decode {path}@{branch}") from error
        blob_sha = data.get("sha")
        if (
            not isinstance(blob_sha, str)
            or len(blob_sha) != 40
            or any(character not in "0123456789abcdef" for character in blob_sha)
        ):
            raise RuntimeError(f"failed to read {path}@{branch}: invalid blob SHA")
        return blob_sha, content

    def put_file(self, path: str, branch: str, content: str, message: str, sha: str | None) -> int:
        payload = {
            "message": message,
            "branch": branch,
            "content": base64.b64encode(content.encode("utf-8")).decode("ascii"),
        }
        if sha:
            payload["sha"] = sha
        status, _ = self._request("PUT", f"/repos/{self._repo}/contents/{path}", payload)
        return status


def _fail(message: str) -> None:
    print(f"::error::{message}", file=sys.stderr)


def read_event() -> dict:
    event_path = os.environ.get("GITHUB_EVENT_PATH")
    if not event_path or not os.path.exists(event_path):
        raise RuntimeError("GITHUB_EVENT_PATH is not set")
    with open(event_path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def read_local_document() -> tuple[bytes, str]:
    with open(DOCUMENT_LOCAL_PATH, "rb") as handle:
        document = handle.read()
    with open(DIGEST_LOCAL_PATH, "r", encoding="utf-8") as handle:
        expected = lib.parse_expected_digest(handle.read())
    return document, expected


def checked_out_commit() -> str:
    result = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    )
    commit = result.stdout.strip()
    if len(commit) != 40 or any(character not in "0123456789abcdef" for character in commit):
        raise RuntimeError("trusted checkout did not resolve to a full Git commit SHA")
    return commit


def document_url(repo: str, document_commit: str) -> str:
    return f"https://github.com/{repo}/blob/{document_commit}/{lib.DOCUMENT_PATH}"


def resolve_pull_number(event_name: str, event: dict) -> int | None:
    if event_name == "pull_request_target":
        return event.get("pull_request", {}).get("number")
    if event_name == "issue_comment":
        issue = event.get("issue", {})
        if "pull_request" not in issue:
            return None
        return issue.get("number")
    return None


def record_acceptance_if_present(
    client: GitHubClient,
    event_name: str,
    event: dict,
    pull: dict,
    required: dict[int, str],
    digest: str,
    document_commit: str,
    doc_url: str,
    default_branch: str,
) -> None:
    if event_name != "issue_comment":
        return
    comment = event.get("comment", {})
    if (comment.get("body") or "").strip() != lib.ASSENT_STATEMENT:
        return
    user = comment.get("user", {})
    user_id = user.get("id")
    if user_id is None or int(user_id) not in required:
        # Only a human contributor to this PR may create a signature record.
        return

    record = lib.make_record(
        repository_id=event["repository"]["id"],
        login=user.get("login", ""),
        user_id=int(user_id),
        pr_number=pull["number"],
        pr_id=pull["id"],
        pr_node_id=pull["node_id"],
        comment_id=comment["id"],
        accepted_at=comment["created_at"],
        document_sha256=digest,
        document_commit=document_commit,
        document_url=doc_url,
    )

    client.ensure_branch(SIGNATURES_BRANCH, default_branch)
    last_status = None
    for _ in range(MAX_LEDGER_WRITE_ATTEMPTS):
        blob_sha, content = client.get_file(SIGNATURES_PATH, SIGNATURES_BRANCH)
        ledger = lib.load_ledger(content)
        if lib.record_exists(ledger.get("records", []), record["commentId"]):
            return
        updated = lib.append_record(ledger, record)
        serialized = lib.serialize_ledger(updated)
        message = f"chore(cla): record ICLA v2.0 acceptance by {record['login']} (PR #{record['prNumber']})"
        last_status = client.put_file(SIGNATURES_PATH, SIGNATURES_BRANCH, serialized, message, blob_sha)
        if last_status in (200, 201):
            return
        if last_status != 409:
            break
    raise lib.LedgerConflictError(
        f"could not update {SIGNATURES_PATH} on {SIGNATURES_BRANCH}: HTTP {last_status}"
    )


def record_covered_pull(
    client: GitHubClient,
    repository_id: int,
    pull: dict,
    commits: list[dict],
    required: dict[int, str],
    default_branch: str,
) -> None:
    """Persist proof that one exact PR head passed the contributor gate."""
    record = lib.make_covered_pull_record(
        repository_id=repository_id,
        pull=pull,
        commits=commits,
        required=required,
    )
    client.ensure_branch(SIGNATURES_BRANCH, default_branch)
    last_status = None
    for _ in range(MAX_LEDGER_WRITE_ATTEMPTS):
        blob_sha, content = client.get_file(SIGNATURES_PATH, SIGNATURES_BRANCH)
        ledger = lib.load_ledger(content)
        updated = lib.append_covered_pull_record(ledger, record)
        serialized = lib.serialize_ledger(updated)
        if serialized == lib.serialize_ledger(ledger):
            return
        message = (
            f"chore(cla): record covered PR #{record['prNumber']} "
            f"at {record['headSha'][:12]}"
        )
        last_status = client.put_file(SIGNATURES_PATH, SIGNATURES_BRANCH, serialized, message, blob_sha)
        if last_status in (200, 201):
            return
        if last_status != 409:
            break
    raise lib.LedgerConflictError(
        f"could not record covered PR in {SIGNATURES_PATH}: HTTP {last_status}"
    )


def build_comment(missing: dict[int, str], doc_url: str) -> str:
    mentions = ", ".join(f"@{login}" for login in sorted(missing.values()))
    return (
        f"{COMMENT_MARKER}\n"
        f"Thanks for the pull request. Before it can be merged, each contributor must accept the "
        f"[Rockxy ICLA v2.0]({doc_url}).\n\n"
        f"{mentions}: please read the agreement, then post this exact comment on this pull request:\n\n"
        f"> {lib.ASSENT_STATEMENT}\n\n"
        f"The `{lib.STATUS_CONTEXT}` check turns green once every contributor has accepted. "
        f"If an employer or organization owns or controls your contribution, contact "
        f"`rockxyapp@gmail.com` about the CCLA before signing."
    )


def build_all_signed_comment(doc_url: str) -> str:
    return (
        f"{COMMENT_MARKER}\n"
        f"All contributors have accepted the [Rockxy ICLA v2.0]({doc_url}). "
        f"The `{lib.STATUS_CONTEXT}` check is green."
    )


def main() -> int:
    token = os.environ.get("GITHUB_TOKEN", "")
    repo = os.environ.get("GITHUB_REPOSITORY", "")
    api_url = os.environ.get("GITHUB_API_URL", "https://api.github.com")
    event_name = os.environ.get("GITHUB_EVENT_NAME", "")
    if not token or not repo:
        _fail("GITHUB_TOKEN and GITHUB_REPOSITORY are required")
        return 1

    event = read_event()
    client = GitHubClient(token, repo, api_url)

    pull_number = resolve_pull_number(event_name, event)
    if pull_number is None:
        # A non-PR issue comment or an unrelated event: nothing to gate.
        return 0

    pull = client.get_pull(pull_number)
    head_sha = pull["head"]["sha"]
    repository = client.get_repository()
    if not lib.merge_policy_preserves_commit_shas(repository):
        client.set_status(
            head_sha,
            "failure",
            "Repository merge policy does not preserve contributor commit SHAs",
        )
        client.upsert_comment(
            pull_number,
            f"{COMMENT_MARKER}\n"
            f"The `{lib.STATUS_CONTEXT}` check is paused because repository merge settings "
            f"must allow merge commits and disable squash/rebase merges. This preserves the "
            f"exact reviewed contributor commit evidence used by the release gate.",
        )
        _fail("repository merge settings do not preserve exact pull-request commit SHAs")
        return 1
    default_branch = event.get("repository", {}).get("default_branch") or "main"
    document_commit = checked_out_commit()
    doc_url = document_url(repo, document_commit)

    document, expected_digest = read_local_document()
    digest_ok, actual_digest = lib.verify_document_digest(document, expected_digest)
    if not digest_ok:
        client.set_status(
            head_sha,
            "failure",
            "ICLA v2.0 document digest mismatch — gate disabled",
        )
        _fail(
            "ICLA v2.0 digest verification failed. "
            f"expected={expected_digest or '<unset>'} actual={actual_digest}"
        )
        return 1

    commits = client.list_pull_commits(pull_number)
    required, unresolved = lib.required_human_contributors(commits, pull.get("user"))

    if unresolved:
        client.set_status(
            head_sha,
            "failure",
            f"{len(unresolved)} commit author(s) not linked to a GitHub account",
        )
        client.upsert_comment(
            pull_number,
            f"{COMMENT_MARKER}\n"
            f"The `{lib.STATUS_CONTEXT}` check cannot verify every contributor because "
            f"{len(unresolved)} commit author(s) are not linked to a GitHub account. "
            f"Please ensure each commit's author email is associated with the GitHub "
            f"account that is accepting the ICLA, then push again.",
        )
        _fail(f"unresolved commit authors: {', '.join(unresolved)}")
        return 1

    record_acceptance_if_present(
        client,
        event_name,
        event,
        pull,
        required,
        actual_digest,
        document_commit,
        doc_url,
        default_branch,
    )

    _, ledger_content = client.get_file(SIGNATURES_PATH, SIGNATURES_BRANCH)
    records = lib.load_ledger(ledger_content).get("records", [])
    missing = lib.evaluate_missing_signers(
        records,
        required,
        pull_number,
        pull["created_at"],
        actual_digest,
    )

    if missing:
        client.set_status(
            head_sha,
            "pending",
            f"Awaiting ICLA v2.0 acceptance from {len(missing)} contributor(s)",
        )
        client.upsert_comment(pull_number, build_comment(missing, doc_url))
        return 0

    record_covered_pull(
        client,
        event["repository"]["id"],
        pull,
        commits,
        required,
        default_branch,
    )
    client.set_status(head_sha, "success", "All contributors accepted the Rockxy ICLA v2.0")
    if client.find_marker_comment(pull_number) is not None:
        client.upsert_comment(pull_number, build_all_signed_comment(doc_url))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
