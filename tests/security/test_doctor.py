#!/usr/bin/env python3
"""Preflight identity assertion (spec §13, §16).

`command -v` reported four tools present on this workstation that were a
Python library and three git aliases. Doctor asserts what a binary *is*, not
that a name resolves — because the failure mode of the alternative is an empty
result set that reads as a clean target.
"""
import os
import sys
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).resolve().parent / "fixtures"
sys.path.insert(0, str(REPO / "scripts" / "security"))

import doctor as D  # noqa: E402
import registry as R  # noqa: E402


def spec(**over):
    base = {
        "description": "A fixture tool used by the doctor tests.",
        "binary": "fake-emit",
        "scope_class": "active",
        "consumes": ["authorized_host"],
        "emits": ["endpoint"],
        "packages": {"kali": "fake-emit-pkg", "debian": "go:example.com/fake@latest",
                     "darwin": "fake-emit"},
        "verify": ["fake-emit", "-version"],
        "expect": "projectdiscovery",
        "argv": ["-count", "{count}"],
        "params": {"count": {"type": "integer", "default": 1, "source": "model"}},
        "parser": "jsonl",
        "taint_fields": ["url"],
        "timeout": 10,
    }
    base.update(over)
    return base


class DoctorCase(unittest.TestCase):
    def setUp(self):
        self._path = os.environ["PATH"]
        os.environ["PATH"] = f"{FIXTURES / 'bin'}{os.pathsep}{self._path}"
        self.addCleanup(lambda: os.environ.__setitem__("PATH", self._path))
        R._IDENTITY_CACHE.clear()


class TestDoctor(DoctorCase):
    def test_a_real_binary_passes_identity(self):
        row = D.check({"faketool": spec()})[0]
        self.assertTrue(row.present)
        self.assertTrue(row.identity_ok)
        self.assertIn("fake-emit", row.path)

    def test_a_missing_binary_is_reported_with_an_install_hint(self):
        row = D.check({"faketool": spec(binary="definitely-not-installed-xyz")})[0]
        self.assertFalse(row.present)
        self.assertFalse(row.identity_ok)
        self.assertIn("fake-emit-pkg", row.install_hint("kali"))

    def test_a_shadowed_binary_fails_identity_not_presence(self):
        # The name-collision trap: the binary on PATH is a different project's.
        row = D.check({"shadowed": spec(binary="fake-imposter",
                                        verify=["fake-imposter", "-version"])})[0]
        self.assertTrue(row.present)
        self.assertFalse(row.identity_ok)
        self.assertIn("projectdiscovery", row.detail)

    def test_install_hint_falls_back_when_a_platform_is_undeclared(self):
        row = D.check({"faketool": spec(binary="nope-xyz", packages={"kali": "only-kali"})})[0]
        self.assertIn("only-kali", row.install_hint("darwin"))

    def test_check_can_be_narrowed_to_named_tools(self):
        reg = {"a": spec(), "b": spec(binary="fake-empty", verify=["fake-empty", "-version"])}
        self.assertEqual([r.name for r in D.check(reg, only=["b"])], ["b"])

    def test_unknown_tool_name_is_an_error(self):
        with self.assertRaises(KeyError):
            D.check({"a": spec()}, only=["nope"])

    def test_report_is_ordered_by_tool_name(self):
        self.assertEqual([r.name for r in D.check({"zeta": spec(), "alpha": spec()})],
                         ["alpha", "zeta"])

    def test_ok_is_false_when_any_tool_fails(self):
        self.assertFalse(D.all_ok(D.check({"good": spec(), "bad": spec(binary="nope-xyz")})))

    def test_ok_is_true_when_every_tool_passes(self):
        self.assertTrue(D.all_ok(D.check({"good": spec()})))

    def test_identity_result_is_cached_per_binary(self):
        reg = {"a": spec(), "b": spec()}
        D.check(reg)
        self.assertGreaterEqual(len(R._IDENTITY_CACHE), 1)


class TestTraps(DoctorCase):
    """§13 — the traps that fail quietly, surfaced before a run rather than after."""

    def test_trap_notes_load(self):
        self.assertTrue(D.load_traps())

    def test_every_trap_entry_names_a_shipped_tool(self):
        import lint as L
        registry = L.load_registry()
        for name in D.load_traps():
            self.assertIn(name, registry, f"trap documented for unknown tool {name}")

    def test_every_trap_entry_explains_the_failure(self):
        for name, note in D.load_traps().items():
            self.assertTrue(note.get("trap"), name)

    def test_traps_are_attached_to_the_report_row(self):
        import lint as L
        name = sorted(D.load_traps())[0]
        self.assertTrue(D.check(L.load_registry(), only=[name])[0].trap)

    def test_a_tool_with_no_trap_reports_none(self):
        self.assertIsNone(D.check({"faketool": spec()})[0].trap)


class TestShippedRegistryPackaging(unittest.TestCase):
    def test_every_shipped_tool_declares_an_install_route(self):
        import lint as L
        for name, s in L.load_registry().items():
            pkgs = s.get("packages", {})
            self.assertTrue(pkgs.get("kali") or pkgs.get("debian"), name)


if __name__ == "__main__":
    unittest.main()
