#!/usr/bin/env python3
"""Unit tests for the Rockxy ICLA v2.0 gate logic (network-free).

Run from the repository root:

    python3 -m unittest discover -s .github/tools/tests -p 'test_*.py'
"""

import hashlib
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), os.pardir))

import cla_lib as lib  # noqa: E402


def _commit(sha, author):
    return {"sha": sha, "author": author}


def _commit_with_message(sha, author, email, message):
    return {
        "sha": sha,
        "author": author,
        "commit": {"author": {"email": email}, "message": message},
    }


def _user(user_id, login):
    return {"id": user_id, "login": login}


def _record(user_id, pr_number, accepted_at, comment_id, login="octo"):
    return lib.make_record(
        repository_id=1192753899,
        login=login,
        user_id=user_id,
        pr_number=pr_number,
        pr_id=pr_number * 1000,
        pr_node_id=f"PR_{pr_number}",
        comment_id=comment_id,
        accepted_at=accepted_at,
        document_sha256="a" * 64,
        document_commit="b" * 40,
        document_url=f"https://github.com/RockxyApp/Rockxy/blob/{'b' * 40}/legal/cla/ICLA-v2.0.md",
    )


class SamePullRequestAssentTests(unittest.TestCase):
    def test_same_pr_assent_covers_that_pr(self):
        records = [_record(500, 42, "2026-08-15T10:00:00Z", 1)]
        missing = lib.evaluate_missing_signers(
            records,
            {500: "octo"},
            target_pr_number=42,
            target_pr_created_at="2026-08-15T09:00:00Z",
            expected_document_sha256="a" * 64,
        )
        self.assertEqual(missing, {})

    def test_missing_when_no_signature(self):
        missing = lib.evaluate_missing_signers(
            [],
            {500: "octo"},
            target_pr_number=42,
            target_pr_created_at="2026-08-15T09:00:00Z",
            expected_document_sha256="a" * 64,
        )
        self.assertEqual(missing, {500: "octo"})


class LaterContributionTests(unittest.TestCase):
    def test_later_pr_is_covered_by_earlier_acceptance(self):
        records = [_record(500, 10, "2026-08-01T00:00:00Z", 1)]
        # PR #77 opened after the acceptance timestamp is a later Contribution.
        missing = lib.evaluate_missing_signers(
            records,
            {500: "octo"},
            target_pr_number=77,
            target_pr_created_at="2026-08-10T00:00:00Z",
            expected_document_sha256="a" * 64,
        )
        self.assertEqual(missing, {})

    def test_pr_opened_exactly_at_acceptance_is_covered(self):
        records = [_record(500, 10, "2026-08-01T00:00:00Z", 1)]
        missing = lib.evaluate_missing_signers(
            records,
            {500: "octo"},
            target_pr_number=77,
            target_pr_created_at="2026-08-01T00:00:00Z",
            expected_document_sha256="a" * 64,
        )
        self.assertEqual(missing, {})


class LaterSignatureDoesNotCoverEarlierTests(unittest.TestCase):
    def test_signature_from_later_pr_does_not_cover_earlier_submission(self):
        # Signature accepted on PR #100 at 2026-08-10 must not cover the
        # earlier-opened PR #50 (opened 2026-08-01).
        records = [_record(500, 100, "2026-08-10T00:00:00Z", 1)]
        missing = lib.evaluate_missing_signers(
            records,
            {500: "octo"},
            target_pr_number=50,
            target_pr_created_at="2026-08-01T00:00:00Z",
            expected_document_sha256="a" * 64,
        )
        self.assertEqual(missing, {500: "octo"})

    def test_record_for_different_document_digest_does_not_cover(self):
        records = [_record(500, 42, "2026-08-15T10:00:00Z", 1)]
        missing = lib.evaluate_missing_signers(
            records,
            {500: "octo"},
            target_pr_number=42,
            target_pr_created_at="2026-08-15T09:00:00Z",
            expected_document_sha256="c" * 64,
        )
        self.assertEqual(missing, {500: "octo"})


class BotExclusionTests(unittest.TestCase):
    def test_exact_bot_ids_and_owner_excluded(self):
        commits = [
            _commit("c1", _user(9362970, "LocNguyenHuu")),   # owner
            _commit("c2", _user(49699333, "dependabot[bot]")),
            _commit("c3", _user(41898282, "github-actions[bot]")),
            _commit("c4", _user(29139614, "renovate[bot]")),
            _commit("c5", _user(12345, "real-human")),
        ]
        required, unresolved = lib.required_human_contributors(commits)
        self.assertEqual(required, {12345: "real-human"})
        self.assertEqual(unresolved, [])

    def test_bot_login_with_unexpected_id_fails_closed(self):
        commits = [_commit("c1", _user(999999, "dependabot[bot]"))]
        required, _ = lib.required_human_contributors(commits)
        self.assertEqual(required, {999999: "dependabot[bot]"})

    def test_unknown_bot_is_treated_as_required_human(self):
        commits = [_commit("c1", _user(777, "some-unknown-bot[bot]"))]
        required, _ = lib.required_human_contributors(commits)
        self.assertEqual(required, {777: "some-unknown-bot[bot]"})

    def test_external_pull_author_is_required_even_when_commits_claim_owner(self):
        commits = [_commit("c1", _user(9362970, "LocNguyenHuu"))]
        required, unresolved = lib.required_human_contributors(
            commits,
            _user(12345, "external-author"),
        )
        self.assertEqual(required, {12345: "external-author"})
        self.assertEqual(unresolved, [])

    def test_numeric_noreply_coauthor_is_required(self):
        commits = [
            _commit_with_message(
                "c1",
                _user(9362970, "LocNguyenHuu"),
                "9362970+LocNguyenHuu@users.noreply.github.com",
                "feature\n\nCo-authored-by: Alice <123456+alice@users.noreply.github.com>",
            )
        ]
        required, unresolved = lib.required_human_contributors(commits)
        self.assertEqual(required, {123456: "alice"})
        self.assertEqual(unresolved, [])

    def test_unresolvable_coauthor_fails_closed(self):
        commits = [
            _commit_with_message(
                "c1",
                _user(9362970, "LocNguyenHuu"),
                "owner@example.com",
                "feature\n\nCo-authored-by: Alice <private@example.com>",
            )
        ]
        required, unresolved = lib.required_human_contributors(commits)
        self.assertEqual(required, {})
        self.assertEqual(unresolved, ["c1:unresolved-coauthor:private@example.com"])


class MergePolicyTests(unittest.TestCase):
    def test_only_merge_commit_policy_preserves_reviewed_commit_shas(self):
        self.assertTrue(
            lib.merge_policy_preserves_commit_shas(
                {
                    "allow_merge_commit": True,
                    "allow_squash_merge": False,
                    "allow_rebase_merge": False,
                }
            )
        )

    def test_squash_or_rebase_policy_fails_closed(self):
        self.assertFalse(
            lib.merge_policy_preserves_commit_shas(
                {
                    "allow_merge_commit": True,
                    "allow_squash_merge": True,
                    "allow_rebase_merge": False,
                }
            )
        )
        self.assertFalse(
            lib.merge_policy_preserves_commit_shas(
                {
                    "allow_merge_commit": True,
                    "allow_squash_merge": False,
                    "allow_rebase_merge": True,
                }
            )
        )


class UnresolvedAuthorFailClosedTests(unittest.TestCase):
    def test_null_author_is_unresolved(self):
        commits = [
            _commit("c1", _user(12345, "real-human")),
            _commit("deadbeef", None),
        ]
        required, unresolved = lib.required_human_contributors(commits)
        self.assertEqual(required, {12345: "real-human"})
        self.assertEqual(unresolved, ["deadbeef"])

    def test_author_without_id_is_unresolved(self):
        commits = [_commit("cafe", {"login": "ghost"})]
        required, unresolved = lib.required_human_contributors(commits)
        self.assertEqual(required, {})
        self.assertEqual(unresolved, ["cafe"])


class LedgerDeterminismTests(unittest.TestCase):
    @staticmethod
    def covered_pull():
        return lib.make_covered_pull_record(
            repository_id=1192753899,
            pull={
                "number": 42,
                "id": 42000,
                "node_id": "PR_42",
                "created_at": "2026-08-01T00:00:00Z",
                "head": {"sha": "c" * 40},
            },
            commits=[_commit("d" * 40, _user(500, "octo"))],
            required={500: "octo"},
        )

    def test_serialization_is_order_independent(self):
        a = _record(2, 20, "2026-08-02T00:00:00Z", 200)
        b = _record(1, 10, "2026-08-01T00:00:00Z", 100)
        forward = lib.serialize_ledger({"iclaVersion": "2.0", "records": [a, b]})
        reverse = lib.serialize_ledger({"iclaVersion": "2.0", "records": [b, a]})
        self.assertEqual(forward, reverse)
        self.assertTrue(forward.endswith("\n"))

    def test_append_is_idempotent_by_comment_id(self):
        ledger = lib.new_ledger()
        rec = _record(1, 10, "2026-08-01T00:00:00Z", 100)
        once = lib.append_record(ledger, rec)
        twice = lib.append_record(once, rec)
        self.assertEqual(len(twice["records"]), 1)
        self.assertEqual(lib.serialize_ledger(once), lib.serialize_ledger(twice))

    def test_append_adds_distinct_comment(self):
        ledger = lib.new_ledger()
        ledger = lib.append_record(ledger, _record(1, 10, "2026-08-01T00:00:00Z", 100))
        ledger = lib.append_record(ledger, _record(1, 30, "2026-08-05T00:00:00Z", 300))
        self.assertEqual(len(ledger["records"]), 2)

    def test_load_ledger_accepts_bootstrap_shape(self):
        ledger = lib.load_ledger('{"signedContributors": []}')
        self.assertEqual(ledger["records"], [])
        self.assertEqual(lib.load_ledger("").get("records"), [])

    def test_load_ledger_rejects_incomplete_or_wrong_assent_evidence(self):
        record = _record(1, 10, "2026-08-01T00:00:00Z", 100)
        record["assentStatement"] = "I agree"
        text = lib.serialize_ledger({"iclaVersion": "2.0", "records": [record]})
        with self.assertRaisesRegex(ValueError, "exact assent statement"):
            lib.load_ledger(text)

    def test_covered_pull_is_append_only_and_idempotent(self):
        ledger = lib.new_ledger()
        record = self.covered_pull()
        once = lib.append_covered_pull_record(ledger, record)
        twice = lib.append_covered_pull_record(once, record)
        self.assertEqual(len(twice["coveredPullRequests"]), 1)
        self.assertEqual(lib.serialize_ledger(once), lib.serialize_ledger(twice))

    def test_load_ledger_rejects_malformed_covered_pull(self):
        record = self.covered_pull()
        record["headSha"] = "not-a-sha"
        text = lib.serialize_ledger(
            {"iclaVersion": "2.0", "records": [], "coveredPullRequests": [record]}
        )
        with self.assertRaisesRegex(ValueError, "headSha"):
            lib.load_ledger(text)


class DigestTests(unittest.TestCase):
    def test_digest_matches(self):
        data = b"hello rockxy icla"
        expected = hashlib.sha256(data).hexdigest()
        ok, actual = lib.verify_document_digest(data, expected)
        self.assertTrue(ok)
        self.assertEqual(actual, expected)

    def test_digest_mismatch_fails_closed(self):
        data = b"hello rockxy icla"
        ok, actual = lib.verify_document_digest(data, "b" * 64)
        self.assertFalse(ok)
        self.assertEqual(actual, hashlib.sha256(data).hexdigest())

    def test_invalid_or_placeholder_digest_fails_closed(self):
        data = b"anything"
        self.assertFalse(lib.verify_document_digest(data, "")[0])
        self.assertFalse(lib.verify_document_digest(data, "PENDING")[0])
        self.assertEqual(lib.parse_expected_digest("PENDING_RECOMPUTE  legal/cla/ICLA-v2.0.md"), "")

    def test_parse_expected_digest_extracts_hex(self):
        digest = "0" * 64
        parsed = lib.parse_expected_digest(f"{digest}  legal/cla/ICLA-v2.0.md\n")
        self.assertEqual(parsed, digest)

    def test_noncanonical_digest_formats_fail_closed(self):
        canonical = "a" * 64
        self.assertTrue(lib.is_valid_sha256(canonical))
        for value in (
            "A" * 64,
            "0x" + "a" * 62,
            "+" + "a" * 63,
            "-" + "a" * 63,
            "a_" + "a" * 62,
            "a" * 63,
            "a" * 65,
        ):
            with self.subTest(value=value):
                self.assertFalse(lib.is_valid_sha256(value))

    def test_legacy_v1_records_never_bootstrap_v2_acceptance(self):
        ledger = lib.load_ledger('{"signedContributors": [{"githubUsername": "someone"}]}')
        self.assertEqual(ledger, lib.new_ledger())


if __name__ == "__main__":
    unittest.main()
