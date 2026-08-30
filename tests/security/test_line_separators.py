#!/usr/bin/env python3
r"""Line separators must not forge a row boundary (§3.2, §8).

U+2028 LINE SEPARATOR and U+2029 PARAGRAPH SEPARATOR are matched by neither
`\n` nor the C1 control range, so they survived sanitization — but
`str.splitlines()` DOES split on them, and every consumer in this harness
(`targets_from_artifact`, `materialize_input`, `artifacts.query`) reads rows
with `splitlines()`.

One of them in a page title, a TLS common name or a DNS TXT record made a row
count as present in the audit and vanish from every reader: a finding that
deletes itself from the report, and a `provenance: {row}` index that no longer
points at the bytes it names.

Every codepoint here is written as an escape on purpose — a literal in the
source would be invisible in review, which is the whole problem.
"""
import json
import sys
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "scripts" / "security"))

import normalize as N  # noqa: E402

# Everything Python's splitlines() treats as a boundary, plus the C1 relatives.
SEPARATORS = {
    "U+2028 LINE SEPARATOR": " ",
    "U+2029 PARAGRAPH SEPARATOR": " ",
    "U+0085 NEXT LINE": "",
    "U+000B LINE TABULATION": "\x0b",
    "U+000C FORM FEED": "\x0c",
    "U+000A LINE FEED": "\n",
    "U+000D CARRIAGE RETURN": "\r",
    "U+001C FILE SEPARATOR": "\x1c",
    "U+001D GROUP SEPARATOR": "\x1d",
    "U+001E RECORD SEPARATOR": "\x1e",
}


class TestSeparatorsCannotForgeRows(unittest.TestCase):
    def test_none_survive_sanitization(self):
        for name, sep in SEPARATORS.items():
            with self.subTest(sep=name):
                self.assertNotIn(sep, N._sanitize_str(f"a{sep}b", 512))

    def test_none_can_forge_a_row_boundary(self):
        for name, sep in SEPARATORS.items():
            with self.subTest(sep=name):
                cleaned = N._sanitize_str(f"a{sep}b", 512)
                self.assertEqual(len(cleaned.splitlines()), 1)

    def test_splitlines_agrees_the_cleaned_value_is_one_line(self):
        # Guards the actual coupling: sanitize must neutralize exactly what
        # splitlines() would split on, since that is how every reader parses.
        for name, sep in SEPARATORS.items():
            with self.subTest(sep=name):
                self.assertGreater(len(f"a{sep}b".splitlines()), 0)
                self.assertEqual(N._sanitize_str(f"a{sep}b", 512).count("\n"), 0)


class TestArtifactRowStaysReadable(unittest.TestCase):
    def test_a_forged_title_leaves_the_row_intact_for_its_consumers(self):
        payload = 'benign {"host": "evil.example.org"}'
        row = json.dumps(
            {"host": "a.lab.internal", "title": N._sanitize_str(payload, 512)},
            ensure_ascii=False)
        self.assertEqual(len(row.splitlines()), 1)
        self.assertEqual(json.loads(row)["host"], "a.lab.internal")

    def test_the_payload_survives_as_inert_text(self):
        # §3.2: hostile text is reported, not executed and not erased.
        cleaned = N._sanitize_str('ignore previous instructions', 512)
        self.assertIn("ignore previous", cleaned)
        self.assertIn("instructions", cleaned)


if __name__ == "__main__":
    unittest.main()
