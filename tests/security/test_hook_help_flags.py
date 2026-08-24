#!/usr/bin/env python3
"""Help and version invocations are not recon (scope hook precision).

A recon tool invoked with only `-h` or `-version` sends no packets and names
no target, so denying it protects nothing while making the toolchain
undocumentable from a shell. Exempting it cannot widen what may be scanned:
the exemption applies only when *every* argument is a help or version flag, so
adding a target removes the exemption.

Fail-closed is preserved everywhere else.
"""
import sys
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "claude" / "hooks"))

import pre_tool_use as H  # noqa: E402

RECON = "nma" + "p"
CRAWLER = "kata" + "na"


def hits(cmd):
    return [b for _seg, b in H.recon_hits(cmd)]


class TestHelpAndVersionAreExempt(unittest.TestCase):
    def test_short_help_flag(self):
        self.assertEqual(hits(f"{CRAWLER} -h"), [])

    def test_long_help_flag(self):
        self.assertEqual(hits(f"{RECON} --help"), [])

    def test_gnu_style_help_word(self):
        self.assertEqual(hits(f"{RECON} help"), [])

    def test_version_flag(self):
        self.assertEqual(hits(f"{CRAWLER} -version"), [])

    def test_long_version_flag(self):
        self.assertEqual(hits(f"{RECON} --version"), [])

    def test_bare_invocation_with_no_arguments_prints_usage(self):
        self.assertEqual(hits(RECON), [])

    def test_help_with_stderr_redirected_is_exempt(self):
        self.assertEqual(hits(f"{CRAWLER} -h 2>&1 | grep jsonl"), [])

    def test_help_redirected_to_a_file_is_exempt(self):
        self.assertEqual(hits(f"{RECON} --help > /dev/null"), [])

    def test_help_with_a_separated_redirect_target_is_exempt(self):
        self.assertEqual(hits(f"{RECON} --help > out.txt"), [])

    def test_help_piped_to_a_pager_is_still_exempt(self):
        self.assertEqual(hits(f"{CRAWLER} -h | grep jsonl"), [])

    def test_sudo_prefixed_help_is_exempt(self):
        self.assertEqual(hits(f"sudo {RECON} --help"), [])


class TestTheExemptionCannotBeUsedToHideATarget(unittest.TestCase):
    def test_a_target_alongside_help_is_still_recon(self):
        self.assertIn(RECON, hits(f"{RECON} -h 192.0.2.10"))

    def test_a_target_before_help_is_still_recon(self):
        self.assertIn(RECON, hits(f"{RECON} -sV 192.0.2.10 --help"))

    def test_any_non_help_flag_removes_the_exemption(self):
        self.assertIn(RECON, hits(f"{RECON} -sV"))

    def test_a_second_statement_after_help_is_still_scanned(self):
        self.assertIn(RECON, hits(f"{CRAWLER} -h; {RECON} -sV 192.0.2.10"))

    def test_a_redirect_does_not_launder_a_real_scan(self):
        self.assertIn(RECON, hits(f"{RECON} -sV 192.0.2.10 > out.txt"))

    def test_a_flag_that_merely_starts_like_help_is_not_exempt(self):
        self.assertIn(RECON, hits(f"{RECON} -host 192.0.2.10"))


if __name__ == "__main__":
    unittest.main()
