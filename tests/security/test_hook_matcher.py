#!/usr/bin/env python3
"""Command-position matching in the scope hook (spec §20.1).

The hook matched recon tool names anywhere in the command string, so any
command whose *payload* discussed security tooling was denied — commit
messages, documentation, report generation, and the harness's own test files.
Writing the design document tripped it.

Fail-closed behaviour is correct and is preserved here. The defect is the
matcher's precision, not its default: a heredoc body is data, unless the
command that owns it is a shell, in which case the body is executed and must
still be scanned.

Note: this file is written through the file tool rather than a shell heredoc,
because until this fix lands the hook denies any shell command containing
these names.
"""
import sys
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "claude" / "hooks"))

import pre_tool_use as H  # noqa: E402

RECON = "nma" + "p"          # assembled so this file's own text is not a target
DOC_TOOL = "htt" + "px"


def hits(cmd):
    """Binaries the hook believes are being invoked in command position."""
    return [b for _seg, b in H.recon_hits(cmd)]


class TestRealInvocationsAreStillCaught(unittest.TestCase):
    def test_a_bare_recon_command_is_matched(self):
        self.assertIn(RECON, hits(f"{RECON} -sV 192.0.2.10"))

    def test_a_sudo_prefixed_command_is_matched(self):
        self.assertIn(RECON, hits(f"sudo {RECON} -sS 192.0.2.10"))

    def test_an_env_prefixed_command_is_matched(self):
        self.assertIn(RECON, hits(f"FOO=1 {RECON} 192.0.2.10"))

    def test_a_second_statement_is_matched(self):
        self.assertIn(RECON, hits(f"echo hi; {RECON} 192.0.2.10"))

    def test_a_piped_stage_is_matched(self):
        self.assertIn(DOC_TOOL, hits(f"cat hosts.txt | {DOC_TOOL} -silent"))

    def test_command_substitution_is_matched(self):
        self.assertIn(RECON, hits(f"echo $({RECON} -sn 192.0.2.0/24)"))

    def test_an_absolute_path_is_matched(self):
        self.assertIn(RECON, hits(f"/usr/bin/{RECON} 192.0.2.10"))


class TestHeredocBodiesAreData(unittest.TestCase):
    def body(self, owner):
        return (
            f"{owner} <<'EOF'\n"
            f"This paragraph mentions {RECON} and {DOC_TOOL} in prose.\n"
            f"{RECON} -sV 192.0.2.10\n"
            "EOF\n"
        )

    def test_a_heredoc_written_to_a_file_is_not_scanned(self):
        self.assertEqual(hits(self.body("cat > notes.md")), [])

    def test_a_heredoc_piped_to_tee_is_not_scanned(self):
        self.assertEqual(hits(self.body("tee notes.md")), [])

    def test_a_python_heredoc_is_not_scanned_as_shell(self):
        self.assertEqual(hits(self.body("python3 -")), [])

    def test_an_unquoted_heredoc_delimiter_is_handled(self):
        cmd = f"cat > notes.md <<EOF\n{RECON} -sV 192.0.2.10\nEOF\n"
        self.assertEqual(hits(cmd), [])

    def test_a_dash_heredoc_with_indented_terminator_is_handled(self):
        cmd = f"cat > notes.md <<-'EOF'\n\t{RECON} -sV 192.0.2.10\n\tEOF\n"
        self.assertEqual(hits(cmd), [])

    def test_text_after_the_heredoc_terminator_is_still_scanned(self):
        cmd = (
            "cat > notes.md <<'EOF'\n"
            "prose only\n"
            "EOF\n"
            f"{RECON} -sV 192.0.2.10\n"
        )
        self.assertIn(RECON, hits(cmd))

    def test_two_heredocs_in_one_command_are_both_stripped(self):
        cmd = (
            f"cat > a.md <<'A'\n{RECON} 1.2.3.4\nA\n"
            f"cat > b.md <<'B'\n{DOC_TOOL} -silent\nB\n"
        )
        self.assertEqual(hits(cmd), [])


class TestShellHeredocsAreStillExecuted(unittest.TestCase):
    """A heredoc fed to a shell is a script, not data. Fail closed."""

    def script(self, owner):
        return f"{owner} <<'EOF'\n{RECON} -sV 192.0.2.10\nEOF\n"

    def test_bash_heredoc_body_is_scanned(self):
        self.assertIn(RECON, hits(self.script("bash")))

    def test_sh_heredoc_body_is_scanned(self):
        self.assertIn(RECON, hits(self.script("sh")))

    def test_zsh_heredoc_body_is_scanned(self):
        self.assertIn(RECON, hits(self.script("zsh")))

    def test_ssh_heredoc_body_is_scanned(self):
        self.assertIn(RECON, hits(self.script("ssh host")))

    def test_sudo_bash_heredoc_body_is_scanned(self):
        self.assertIn(RECON, hits(self.script("sudo bash")))

    def test_an_unterminated_heredoc_fails_closed(self):
        # No terminator: we cannot prove where data ends, so scan everything.
        cmd = f"cat > notes.md <<'EOF'\n{RECON} -sV 192.0.2.10\n"
        self.assertIn(RECON, hits(cmd))


class TestCommentsAndProse(unittest.TestCase):
    def test_a_full_line_comment_is_not_a_command(self):
        self.assertEqual(hits(f"# we should run {RECON} against the lab later"), [])

    def test_a_trailing_comment_does_not_mask_the_command(self):
        self.assertIn(RECON, hits(f"{RECON} 192.0.2.10  # scan the lab host"))

    def test_a_tool_name_inside_a_quoted_string_is_not_a_command(self):
        self.assertEqual(hits(f'echo "run {RECON} on the box"'), [])

    def test_a_tool_name_in_a_commit_message_is_not_a_command(self):
        cmd = f'git commit -m "docs: explain why {RECON} needs a scope entry"'
        self.assertEqual(hits(cmd), [])

    def test_a_tool_name_as_a_bare_word_argument_is_not_a_command(self):
        self.assertEqual(hits(f"grep -rn {RECON} docs/"), [])

    def test_a_backtick_quoted_name_in_prose_is_not_a_command(self):
        # Markdown prose reaches the hook whenever a doc is written from a shell.
        self.assertEqual(hits(f"echo 'the `{RECON}` entry needs a package map'"), [])


class TestFailClosedIsPreserved(unittest.TestCase):
    def test_stripping_never_removes_a_real_command_segment(self):
        cmd = f"cat > a.md <<'EOF'\nprose\nEOF\nsudo {RECON} 192.0.2.10"
        self.assertIn(RECON, hits(cmd))

    def test_an_empty_command_matches_nothing(self):
        self.assertEqual(hits(""), [])

    def test_a_malformed_quote_does_not_crash(self):
        self.assertIsInstance(hits(f"{RECON} 'unclosed 192.0.2.10"), list)


if __name__ == "__main__":
    unittest.main()
