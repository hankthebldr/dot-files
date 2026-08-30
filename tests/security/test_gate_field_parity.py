#!/usr/bin/env python3
"""The gate and the input materializer must read the same fields (§4.1, §6.2).

registry.py held two vocabularies for "what host does this row name":

    targets_from_artifact()  host | hostname | address | ip | url
    materialize_input()      FIELD_FOR_TYPE + _FIELD_FALLBACKS, which add
                             domain, value, matched-at, name, path

A row keyed on one of the extras produced ZERO targets, so `invoke()`'s gate
loop never ran and the verdict fell through to allow — while the materializer
happily wrote that host into the scanner's -list file. The harness's own
phase-0 seed is `{"domain": ...}`, so the most reachable instance used the
pipeline's own artifact.

Scheme-less URLs were the same hole by another route:
`urlparse("example.com:8080/admin").hostname` is None, because Python reads
`example.com` as the scheme — and scheme-less endpoint rows are exactly what
these scanners emit.

Two invariants are pinned here:
  1. Field parity — every field the materializer can use, the gate can read.
  2. Fail closed — rows present but no targets recognised is a denial, not a
     pass. A parser gap must never be an authorization gap.
"""
import json
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "scripts" / "security"))

import engagement as E  # noqa: E402
import registry as R  # noqa: E402


class TestFieldParity(unittest.TestCase):
    def test_every_materializer_field_is_readable_by_the_gate(self):
        missing = sorted(set(R._FIELD_FALLBACKS) - set(R.GATE_FIELDS))
        self.assertEqual(missing, [], f"materializer fields the gate cannot read: {missing}")

    def test_every_declared_type_field_is_readable_by_the_gate(self):
        # `path` names a wordlist, not a host, and is deliberately excluded.
        host_bearing = {f for t, f in R.FIELD_FOR_TYPE.items() if t != "wordlist"}
        missing = sorted(host_bearing - set(R.GATE_FIELDS))
        self.assertEqual(missing, [], f"typed fields the gate cannot read: {missing}")


class ArtifactCase(unittest.TestCase):
    """Drive the real invoke() against the shipped registry and a temp scope."""

    scope_text = "resolve-policy: enforce\n*.lab.internal\n192.0.2.0/24\n"

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        (self.tmp / "eng" / "scans").mkdir(parents=True)
        self.scope = self.tmp / "scope.txt"
        self.scope.write_text(self.scope_text)

    def artifact(self, rows) -> Path:
        p = self.tmp / "eng" / "scans" / "input.jsonl"
        p.write_text("".join(json.dumps(r) + "\n" for r in rows), encoding="utf-8")
        return p

    def invoke(self, rows, tool="naabu"):
        ctx = E.build(self.tmp / "eng", run_id="t", scope_path=str(self.scope),
                      registry_path=str(REPO / "config" / "security" / "tools.yaml"))
        ctx.dry_run = True
        return R.invoke(tool, {"input_file": str(self.artifact(rows))}, ctx)


class TestRowsThatOnceEscaped(ArtifactCase):
    def test_a_domain_row_is_gated(self):
        # The apex does not match *.lab.internal, so this must be refused.
        r = self.invoke([{"domain": "lab.internal"}])
        self.assertEqual(r.status, R.Status.DENIED_SCOPE)
        self.assertIn("lab.internal", r.reason)

    def test_a_value_row_is_gated(self):
        r = self.invoke([{"value": "evil.example.org"}])
        self.assertEqual(r.status, R.Status.DENIED_SCOPE)

    def test_a_matched_at_row_is_gated(self):
        r = self.invoke([{"matched-at": "https://evil.example.org/x"}])
        self.assertEqual(r.status, R.Status.DENIED_SCOPE)

    def test_a_scheme_less_url_row_is_gated(self):
        r = self.invoke([{"url": "evil.example.com:8080/admin"}])
        self.assertEqual(r.status, R.Status.DENIED_SCOPE)
        self.assertIn("evil.example.com", r.reason)

    def test_an_authorized_domain_row_still_passes_the_name_check(self):
        # web.lab.internal matches *.lab.internal; it fails only on the address
        # check under enforce, which proves the gate saw the host at all.
        r = self.invoke([{"domain": "web.lab.internal"}])
        self.assertEqual(r.status, R.Status.DENIED_SCOPE)
        self.assertIn("web.lab.internal", r.reason)
        self.assertNotIn("recognises", r.reason)   # not the fail-closed path


class TestFailClosed(ArtifactCase):
    def test_rows_naming_no_recognisable_host_are_denied(self):
        r = self.invoke([{"note": "nothing here"}, {"other": "still nothing"}])
        self.assertEqual(r.status, R.Status.DENIED_SCOPE)
        self.assertIn("recognises", r.reason)

    def test_the_denial_records_how_many_rows_were_unreadable(self):
        r = self.invoke([{"note": "a"}, {"note": "b"}, {"note": "c"}])
        self.assertIn("3 row(s)", r.reason)

    def test_a_genuinely_empty_artifact_is_not_forced_into_a_denial(self):
        # Nothing to scan is not the same as something unreadable; an upstream
        # phase legitimately produces an empty set.
        r = self.invoke([])
        self.assertNotEqual(r.status, R.Status.DENIED_SCOPE)


class TestTargetsFromArtifact(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())

    def write(self, rows) -> Path:
        p = self.tmp / "a.jsonl"
        p.write_text("".join(json.dumps(r) + "\n" for r in rows), encoding="utf-8")
        return p

    def test_it_reports_rows_seen_alongside_targets(self):
        targets, rows = R.targets_from_artifact(
            self.write([{"host": "a.lab.internal"}, {"note": "x"}]))
        self.assertEqual([h for h, _ in targets], ["a.lab.internal"])
        self.assertEqual(rows, 2)

    def test_a_missing_file_yields_no_rows(self):
        self.assertEqual(R.targets_from_artifact(self.tmp / "nope.jsonl"), ([], 0))

    def test_scheme_less_and_schemed_urls_both_resolve(self):
        for value, expected in [
            ("https://a.lab.internal/x", "a.lab.internal"),
            ("a.lab.internal:8080/admin", "a.lab.internal"),
            ("a.lab.internal/admin", "a.lab.internal"),
            ("//a.lab.internal/admin", "a.lab.internal"),
        ]:
            with self.subTest(value=value):
                self.assertEqual(R._host_from_url(value), expected)

    def test_a_url_that_names_no_host_is_not_invented(self):
        for value in ["", "   ", "/just/a/path"]:
            with self.subTest(value=value):
                self.assertIsNone(R._host_from_url(value))


if __name__ == "__main__":
    unittest.main()
