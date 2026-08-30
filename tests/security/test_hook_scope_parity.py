#!/usr/bin/env python3
"""The hook and the harness must reach the same scope verdict (build order §18.10).

Two independent scope implementations were live at once: `_lib.in_scope` in the
Claude Code hook, and `scope.Scope`/`authorize` in the harness. Same file,
different parsers — so the hook could allow a target the harness denied.

That is the confused-deputy surface §3 T1 exists to close, and it failed in the
dangerous direction: `_lib` had no concept of a `!deny` entry, so it read one as
an ordinary allow-list name that simply never matched, and the exclusion
vanished. An operator writing

    *.lab.example.com
    !prod.lab.example.com

was protected by `claw sec` and unprotected by the hook.

These tests pin the two together at the layer they actually share.

The hook is a *pre*-execution gate with no resolver: it sees a command line, not
a DNS answer. The harness's `authorize()` additionally verifies resolved
addresses under `resolve-policy` (§5.2), and its default is `enforce` whenever
the scope declares any CIDR — so `authorize(host, [], ...)` denies every name
for want of an address. That is correct for the harness and unreachable for the
hook, so full-verdict parity is the wrong contract.

What must agree is the **name/deny half**: which entries grant authority, which
`!entries` remove it, and what the `*.suffix` grammar means. That is
`not scope.denied(host, []) and scope.name_allows(host)` — and it is exactly
what `_lib.in_scope` is answering. `TestHookNeverOutrunsTheHarness` then pins
the one-way safety property that matters: the hook may never allow what the
full harness gate denies.
"""
import sys
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "claude" / "hooks"))
sys.path.insert(0, str(REPO / "scripts" / "security"))

import _lib  # noqa: E402
import scope as S  # noqa: E402


class ScopeParityCase(unittest.TestCase):
    """Point both implementations at one scope file and compare verdicts."""

    scope_text = ""

    def setUp(self):
        import tempfile

        self.tmp = Path(tempfile.mkdtemp())
        self.scope_file = self.tmp / "scope.txt"
        self.scope_file.write_text(self.scope_text)
        self._saved = _lib.SCOPE_FILE
        _lib.SCOPE_FILE = self.scope_file
        self.scope = S.Scope.from_files(self.scope_file)

    def tearDown(self):
        _lib.SCOPE_FILE = self._saved

    def name_authority(self, target):
        """The harness's name/deny verdict — the half the hook can evaluate."""
        return (not self.scope.denied(target, [])) and self.scope.name_allows(target)

    def assertParity(self, target, expected):
        hook = _lib.in_scope(target)
        harness = self.name_authority(target)
        self.assertEqual(
            harness, expected,
            f"harness name authority for {target!r} changed — fix the test, not the gate")
        self.assertEqual(
            hook, harness,
            f"{target!r}: hook says {hook}, harness says {harness}")


class TestDenyEntries(ScopeParityCase):
    """`!entry` removes authority. The hook used to ignore it entirely."""

    scope_text = """
# allow the lab, carve out one production host
*.lab.example.com
!prod.lab.example.com
192.168.1.0/24
!192.168.1.50
"""

    def test_an_allowed_name_stays_allowed(self):
        self.assertParity("web.lab.example.com", True)

    def test_a_denied_name_is_denied_by_both(self):
        self.assertParity("prod.lab.example.com", False)

    def test_an_allowed_address_stays_allowed(self):
        self.assertParity("192.168.1.10", True)

    def test_a_denied_address_is_denied_by_both(self):
        self.assertParity("192.168.1.50", False)

    def test_an_unlisted_target_is_denied_by_both(self):
        self.assertParity("evil.example.org", False)


class TestWildcardForm(ScopeParityCase):
    """`*.suffix` is the only wildcard the grammar defines (§5.3)."""

    scope_text = "*.lab.example.com\n"

    def test_a_subdomain_matches(self):
        self.assertParity("web.lab.example.com", True)

    def test_a_deeper_subdomain_matches(self):
        self.assertParity("a.b.lab.example.com", True)

    def test_the_bare_apex_does_not_match(self):
        self.assertParity("lab.example.com", False)

    def test_a_suffix_lookalike_does_not_match(self):
        # evil-lab.example.com must not satisfy *.lab.example.com
        self.assertParity("evil-lab.example.com", False)


class TestDirectives(ScopeParityCase):
    """A `resolve-policy:` line is a directive, never a matchable name."""

    scope_text = "resolve-policy: warn\n*.lab.example.com\n"

    def test_the_directive_is_not_a_target(self):
        self.assertParity("resolve-policy", False)

    def test_the_allow_entry_still_works(self):
        self.assertParity("web.lab.example.com", True)


class TestCaseAndWhitespace(ScopeParityCase):
    scope_text = "  *.LAB.example.com  \n"

    def test_matching_is_case_insensitive(self):
        self.assertParity("WEB.lab.EXAMPLE.com", True)


class TestEmptyScope(ScopeParityCase):
    """Default-deny: an empty scope authorizes nothing."""

    scope_text = "# nothing allowed yet\n"

    def test_nothing_is_in_scope(self):
        self.assertParity("anything.example.com", False)

    def test_an_empty_target_is_not_in_scope(self):
        self.assertFalse(_lib.in_scope(""))


class TestMalformedScopeFailsClosed(unittest.TestCase):
    """A scope file the harness rejects must not silently authorize in the hook."""

    def setUp(self):
        import tempfile

        self.tmp = Path(tempfile.mkdtemp())
        self.scope_file = self.tmp / "scope.txt"
        self.scope_file.write_text("*.lab.example.com\n!\n")  # bare '!' denies nothing
        self._saved = _lib.SCOPE_FILE
        _lib.SCOPE_FILE = self.scope_file

    def tearDown(self):
        _lib.SCOPE_FILE = self._saved

    def test_the_harness_rejects_it(self):
        with self.assertRaises(S.ScopeParseError):
            S.Scope.from_files(self.scope_file)

    def test_the_hook_authorizes_nothing_from_it(self):
        self.assertFalse(_lib.in_scope("web.lab.example.com"))


class TestHookNeverOutrunsTheHarness(ScopeParityCase):
    """The safety property: the hook must not allow what the full gate denies.

    Parity above is on the name/deny half. This closes the other direction —
    across a spread of scopes and targets, there must be no case where the hook
    says yes and `authorize()` says no on *name or deny* grounds. (Address
    verdicts are excluded: the hook has no resolver, and a resolve-policy denial
    is the harness doing strictly more, not the two disagreeing.)
    """

    scope_text = """
*.lab.example.com
!prod.lab.example.com
10.0.0.0/8
!10.1.2.3
resolve-policy: warn
"""

    TARGETS = [
        "web.lab.example.com", "prod.lab.example.com", "a.b.lab.example.com",
        "lab.example.com", "evil-lab.example.com", "evil.example.org",
        "10.0.0.5", "10.1.2.3", "192.0.2.1", "", "resolve-policy",
    ]

    def test_the_hook_never_allows_what_the_gate_denies(self):
        for target in self.TARGETS:
            with self.subTest(target=target):
                if not _lib.in_scope(target):
                    continue                      # hook denies: always safe
                verdict = S.authorize(target, [], self.scope, "active")
                self.assertTrue(
                    verdict.allowed,
                    f"{target!r}: hook allows, harness denies ({verdict.reason})")


class TestUnreachableScopeModule(unittest.TestCase):
    """Borrowing scope.py adds a way to fail that the old inline parser lacked.

    If the harness tree is missing or unimportable — a partial install, a
    renamed checkout — the hook must authorize nothing rather than fall back to
    something permissive.
    """

    def setUp(self):
        import tempfile

        self.tmp = Path(tempfile.mkdtemp())
        self.scope_file = self.tmp / "scope.txt"
        self.scope_file.write_text("*.lab.example.com\n")
        self._saved_file = _lib.SCOPE_FILE
        self._saved_mod = _lib._scope_module
        _lib.SCOPE_FILE = self.scope_file
        _lib._scope_module = lambda: None

    def tearDown(self):
        _lib.SCOPE_FILE = self._saved_file
        _lib._scope_module = self._saved_mod

    def test_an_otherwise_valid_target_is_denied(self):
        self.assertFalse(_lib.in_scope("web.lab.example.com"))

    def test_the_module_is_reachable_in_a_normal_checkout(self):
        # Guards the path resolution itself: with the patch lifted, the real
        # lookup must find scope.py from this repo layout.
        self.assertIsNotNone(self._saved_mod())


class TestMissingScopeFile(unittest.TestCase):
    def setUp(self):
        import tempfile

        self.tmp = Path(tempfile.mkdtemp())
        self._saved = _lib.SCOPE_FILE
        _lib.SCOPE_FILE = self.tmp / "does-not-exist.txt"

    def tearDown(self):
        _lib.SCOPE_FILE = self._saved

    def test_absent_scope_authorizes_nothing(self):
        self.assertFalse(_lib.in_scope("web.lab.example.com"))


if __name__ == "__main__":
    unittest.main()
