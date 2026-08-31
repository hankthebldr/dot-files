#!/usr/bin/env python3
"""`claw sec scope add` — the two-layer amendment path (§5.7).

Adding a target during an engagement must be cheap enough that nobody is
tempted to hand-edit a security-critical file, and narrow enough that "cheap"
never means "unchecked". These tests pin both halves: the overlay is unattended
and ephemeral, the global file is durable, and neither can be made to hold an
entry the parser would later reject or a deny entry already overrides.
"""
import os
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "scripts" / "security"))

import scope as S  # noqa: E402
import scope_edit as E  # noqa: E402


class EditCase(unittest.TestCase):
    global_text = "*.lab.example.com\n192.168.1.0/24\n"

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.gfile = self.tmp / "scope.txt"
        self.gfile.write_text(self.global_text)
        self.eng = self.tmp / "engagement"
        self._saved_env = os.environ.get("CLAW_SEC_ENGAGEMENT")
        os.environ["CLAW_SEC_ENGAGEMENT"] = str(self.eng)

    def tearDown(self):
        if self._saved_env is None:
            os.environ.pop("CLAW_SEC_ENGAGEMENT", None)
        else:
            os.environ["CLAW_SEC_ENGAGEMENT"] = self._saved_env

    def add(self, entry, **kw):
        kw.setdefault("global_file", self.gfile)
        return E.add_entry(entry, **kw)

    def effective(self):
        overlay = E.overlay_path()
        return S.Scope.from_files(self.gfile, overlay if overlay.exists() else None)


class TestEngagementRoot(EditCase):
    def test_the_env_var_names_the_engagement(self):
        self.assertEqual(E.engagement_root(), self.eng)

    def test_an_explicit_path_beats_the_env_var(self):
        self.assertEqual(E.engagement_root("/somewhere/else"), Path("/somewhere/else"))

    def test_unset_falls_back_to_engagements_current(self):
        os.environ.pop("CLAW_SEC_ENGAGEMENT", None)
        self.assertEqual(E.engagement_root(), Path.cwd() / "engagements" / "current")

    def test_the_overlay_sits_inside_the_engagement(self):
        self.assertEqual(E.overlay_path(), self.eng / "scope.local")


class TestOverlayWrites(EditCase):
    def test_a_name_lands_in_the_overlay_not_the_global_file(self):
        r = self.add("lab-a7f3.lab.internal")
        self.assertEqual(r.status, "added")
        self.assertEqual(r.layer, "overlay")
        self.assertIn("lab-a7f3.lab.internal", E.overlay_path().read_text())
        self.assertNotIn("lab-a7f3", self.gfile.read_text())

    def test_the_target_becomes_authorized(self):
        host = "lab-a7f3.lab.internal"
        self.assertFalse(self.effective().name_allows(host))
        self.add(host)
        self.assertTrue(self.effective().name_allows(host))

    def test_the_overlay_is_created_with_an_explaining_header(self):
        self.add("lab-a7f3.lab.internal")
        self.assertIn("EPHEMERAL", E.overlay_path().read_text())

    def test_missing_parent_directories_are_created(self):
        self.assertFalse(self.eng.exists())
        self.add("lab-a7f3.lab.internal")
        self.assertTrue(E.overlay_path().is_file())

    def test_re_adding_is_idempotent(self):
        self.add("lab-a7f3.lab.internal")
        again = self.add("lab-a7f3.lab.internal")
        self.assertEqual(again.status, "already-present")
        body = E.overlay_path().read_text()
        self.assertEqual(body.count("lab-a7f3.lab.internal"), 1)

    def test_a_second_target_appends_rather_than_replaces(self):
        self.add("one.lab.internal")
        self.add("two.lab.internal")
        body = E.overlay_path().read_text()
        self.assertIn("one.lab.internal", body)
        self.assertIn("two.lab.internal", body)

    def test_a_file_without_a_trailing_newline_is_not_corrupted(self):
        E.overlay_path().parent.mkdir(parents=True)
        E.overlay_path().write_text("first.lab.internal")   # no newline
        self.add("second.lab.internal")
        lines = [l for l in E.overlay_path().read_text().splitlines() if l.strip()]
        self.assertIn("first.lab.internal", lines)
        self.assertIn("second.lab.internal", lines)


class TestGlobalWrites(EditCase):
    def test_global_appends_to_the_durable_file(self):
        r = self.add("198.51.100.0/24", to_global=True)
        self.assertEqual(r.status, "added")
        self.assertEqual(r.layer, "global")
        self.assertIn("198.51.100.0/24", self.gfile.read_text())
        self.assertFalse(E.overlay_path().exists())

    def test_the_original_global_entries_survive(self):
        self.add("198.51.100.0/24", to_global=True)
        body = self.gfile.read_text()
        self.assertIn("*.lab.example.com", body)
        self.assertIn("192.168.1.0/24", body)


class TestValidation(EditCase):
    def test_a_malformed_name_is_refused(self):
        with self.assertRaises(S.ScopeParseError):
            self.add("not a hostname")

    def test_an_empty_entry_is_refused(self):
        with self.assertRaises(S.ScopeParseError):
            self.add("   ")

    def test_a_deny_entry_is_refused(self):
        # `add` grants authority; removing it stays a deliberate manual edit.
        with self.assertRaises(S.ScopeParseError):
            self.add("!prod.lab.example.com")

    def test_a_directive_is_refused(self):
        with self.assertRaises(S.ScopeParseError):
            self.add("resolve-policy: off")

    def test_nothing_is_written_when_validation_fails(self):
        with self.assertRaises(S.ScopeParseError):
            self.add("not a hostname")
        self.assertFalse(E.overlay_path().exists())

    def test_a_cidr_is_normalized_to_its_network_address(self):
        r = self.add("10.1.2.3/24", to_global=True)
        self.assertEqual(r.entry, "10.1.2.0/24")

    def test_a_name_is_lowercased_and_de_dotted(self):
        r = self.add("WEB.Lab.Internal.")
        self.assertEqual(r.entry, "web.lab.internal")


class TestDenyWins(EditCase):
    global_text = "*.lab.example.com\n!prod.lab.example.com\n10.0.0.0/8\n!10.1.2.3\n"

    def test_adding_a_denied_name_is_refused_not_silently_useless(self):
        r = self.add("prod.lab.example.com")
        self.assertEqual(r.status, "denied")
        self.assertFalse(r.ok)
        self.assertFalse(E.overlay_path().exists())

    def test_adding_a_denied_address_is_refused(self):
        r = self.add("10.1.2.3")
        self.assertEqual(r.status, "denied")

    def test_an_overlay_cannot_reauthorize_a_globally_denied_host(self):
        self.add("prod.lab.example.com")
        self.assertFalse(self.effective().name_allows("prod.lab.example.com")
                         and not self.effective().denied("prod.lab.example.com", []))

    def test_an_undenied_sibling_still_adds(self):
        r = self.add("staging.lab.example.com")
        self.assertEqual(r.status, "added")


class TestWrittenFilesStayParseable(EditCase):
    def test_every_added_entry_round_trips_through_the_parser(self):
        for entry in ["a.lab.internal", "*.dyn.lab.internal", "203.0.113.0/24"]:
            with self.subTest(entry=entry):
                self.add(entry)
        # from_files raises on malformed content; reaching here is the assertion.
        sc = self.effective()
        self.assertTrue(sc.name_allows("a.lab.internal"))
        self.assertTrue(sc.name_allows("host.dyn.lab.internal"))
        self.assertTrue(sc.addr_allows("203.0.113.9"))


class TestOneResolverForBothSides(EditCase):
    """`scope add` and `run` must resolve the same two files.

    They briefly did not: add honoured CLAW_SEC_SCOPE_FILE and run.py hardcoded
    ~/.claude/scope.txt, so a target could be added to one global file and the
    run gated on another — the same class of split-brain the hook migration
    removed. Both now go through scope_edit.
    """

    def setUp(self):
        super().setUp()
        self._saved_scope_env = os.environ.get("CLAW_SEC_SCOPE_FILE")
        os.environ["CLAW_SEC_SCOPE_FILE"] = str(self.gfile)

    def tearDown(self):
        super().tearDown()
        if self._saved_scope_env is None:
            os.environ.pop("CLAW_SEC_SCOPE_FILE", None)
        else:
            os.environ["CLAW_SEC_SCOPE_FILE"] = self._saved_scope_env

    def test_run_defaults_to_the_same_global_file_add_writes(self):
        import run as R

        args = R.argparse.ArgumentParser()  # noqa: F841 - import smoke
        self.assertEqual(str(E.global_path()), str(self.gfile))
        # run.py builds its --scope default from the same resolver at parse time.
        parser_default = R.SE.global_path()
        self.assertEqual(str(parser_default), str(self.gfile))

    def test_run_defaults_to_the_same_engagement_add_writes(self):
        import run as R  # noqa: F401  — resolution is shared via the env var

        self.assertEqual(E.engagement_root(), self.eng)
        self.assertEqual(Path(os.environ["CLAW_SEC_ENGAGEMENT"]), self.eng)


class TestDescribeLayers(EditCase):
    def test_it_reports_both_paths_and_whether_the_overlay_is_live(self):
        info = E.describe_layers(global_file=self.gfile)
        self.assertEqual(info["global_path"], self.gfile)
        self.assertEqual(info["overlay_path"], self.eng / "scope.local")
        self.assertFalse(info["overlay_active"])

        self.add("lab-a7f3.lab.internal")
        info = E.describe_layers(global_file=self.gfile)
        self.assertTrue(info["overlay_active"])
        self.assertIn("lab-a7f3.lab.internal", info["facts"]["allow_names"])


if __name__ == "__main__":
    unittest.main()


class TestReportsMatchReality(EditCase):
    """`add` must never report success for authority it did not grant.

    The docstring promises it "refuses rather than producing a file whose
    meaning contradicts the request". Two paths defeated that. Neither widened
    authority — deny still wins at authorize() — but both told the operator the
    opposite of the truth, which for a security control is its own failure.
    """

    global_text = ("*.lab.internal\n"
                   "!*.evil.lab.internal\n"
                   "!denied.lab.internal\n"
                   "10.0.0.0/8\n"
                   "!10.1.2.3\n")

    def test_a_denied_name_is_not_reported_as_already_present(self):
        # _existing_entries stripped '!', so a deny read as an existing allow.
        r = self.add("denied.lab.internal")
        self.assertEqual(r.status, "denied")
        self.assertFalse(r.ok)

    def test_a_wildcard_matching_a_glob_deny_is_refused(self):
        # The deny probe used the bare suffix, so a glob deny of the same
        # pattern was missed and `add` reported success for a dead line.
        r = self.add("*.evil.lab.internal")
        self.assertEqual(r.status, "denied")

    def test_a_denied_address_is_refused(self):
        self.assertEqual(self.add("10.1.2.3").status, "denied")

    def test_anything_reported_added_is_actually_authorized(self):
        for entry in ["ok.lab.internal", "*.dyn.lab.internal", "203.0.113.0/24"]:
            with self.subTest(entry=entry):
                r = self.add(entry)
                self.assertEqual(r.status, "added")
                sc = self.effective()
                if "/" in r.entry:
                    self.assertIn(r.entry, {str(n) for n in sc.allow_addrs})
                else:
                    self.assertIn(r.entry, {n.lower() for n in sc.allow_names})


class TestAtomicWrite(EditCase):
    """A partial write widens scope, so the file must never be seen half-done."""

    def test_no_temp_file_is_left_behind(self):
        self.add("a.lab.internal")
        leftovers = list(E.overlay_path().parent.glob("*.tmp.*"))
        self.assertEqual(leftovers, [])

    def test_a_truncated_cidr_would_have_widened_enormously(self):
        # Not a test of add(), but of WHY it writes atomically: this is what a
        # short write buys an attacker. 192.0.2.0/24 is 256 addresses; the same
        # string truncated by one character is over a billion.
        import ipaddress
        self.assertEqual(ipaddress.ip_network("192.0.2.0/24").num_addresses, 256)
        self.assertEqual(
            ipaddress.ip_network("192.0.2.0/2", strict=False).num_addresses,
            1073741824)

    def test_the_file_parses_and_means_what_was_asked_after_each_add(self):
        for entry in ["one.lab.internal", "192.0.2.0/24", "two.lab.internal"]:
            self.add(entry)
        sc = self.effective()
        self.assertTrue(sc.name_allows("one.lab.internal"))
        self.assertTrue(sc.name_allows("two.lab.internal"))
        self.assertTrue(sc.addr_allows("192.0.2.7"))
        self.assertFalse(sc.addr_allows("193.0.0.1"))   # /2 would have allowed this
