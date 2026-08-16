#!/usr/bin/env python3
"""Network-free tests for GitHub API response handling in the CLA gate."""

import base64
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), os.pardir))

import cla_gate  # noqa: E402


class StubClient(cla_gate.GitHubClient):
    def __init__(self, response):
        super().__init__("token", "RockxyApp/Rockxy", "https://api.github.test")
        self.response = response

    def _request(self, method, path, payload=None):
        return self.response


class GetFileTests(unittest.TestCase):
    def test_decodes_wrapped_base64_content(self):
        encoded = base64.b64encode(b'{"records": []}\n').decode("ascii")
        wrapped = f"{encoded[:8]}\n{encoded[8:]}\n"
        client = StubClient((200, {"sha": "blob-sha", "encoding": "base64", "content": wrapped}))
        self.assertEqual(
            client.get_file("signatures/icla-v2.0.json", "cla-signatures"),
            ("blob-sha", '{"records": []}\n'),
        )

    def test_missing_file_is_the_only_empty_result(self):
        client = StubClient((404, None))
        self.assertEqual(client.get_file("missing", "cla-signatures"), (None, ""))

    def test_non_base64_or_empty_content_fails_closed(self):
        for data in (
            {"sha": "blob-sha", "encoding": "none", "content": "payload"},
            {"sha": "blob-sha", "encoding": "base64", "content": ""},
            {"sha": "blob-sha", "encoding": "base64", "content": "%%%"},
        ):
            with self.subTest(data=data):
                client = StubClient((200, data))
                with self.assertRaisesRegex(RuntimeError, "failed to"):
                    client.get_file("ledger", "cla-signatures")


if __name__ == "__main__":
    unittest.main()
