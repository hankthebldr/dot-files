#!/usr/bin/env python3
"""Case table for scripts/security/scope.py (spec §5, §15).

Every case is offline: no DNS, no network, no model. `authorize()` is handed
already-resolved addresses because resolution is the caller's job (§5.1).

Run: python3 -m unittest discover -s tests/security -v
"""
import sys
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "scripts" / "security"))

import scope as S  # noqa: E402


def mkscope(text, overlay=None):
    """Build a Scope from literal file text (and optional overlay text)."""
    return S.Scope.from_text(text, overlay_text=overlay)


# --------------------------------------------------------------------------
# Grammar (§5.3)
# --------------------------------------------------------------------------
class TestGrammar(unittest.TestCase):
    def test_comments_and_blank_lines_are_ignored(self):
        sc = mkscope("# a comment\n\n   \n*.lab.example.com\n")
        self.assertEqual(sc.allow_names, ["*.lab.example.com"])
        self.assertEqual(sc.deny_names, [])

    def test_inline_comment_is_stripped(self):
        sc = mkscope("192.0.2.0/24   # the lab range\n")
        self.assertEqual(len(sc.allow_addrs), 1)

    def test_bang_prefix_denies_a_name(self):
        sc = mkscope("*.lab.example.com\n!status.lab.example.com\n")
        self.assertEqual(sc.deny_names, ["status.lab.example.com"])

    def test_bang_prefix_denies_a_cidr(self):
        sc = mkscope("!198.51.100.0/24\n")
        self.assertEqual(len(sc.deny_addrs), 1)

    def test_bare_bang_is_a_parse_error_not_a_noop(self):
        with self.assertRaises(S.ScopeParseError):
            mkscope("*.lab.example.com\n!\n")

    def test_unknown_directive_is_a_parse_error(self):
        # A typo'd directive must not silently downgrade the control.
        with self.assertRaises(S.ScopeParseError) as cm:
            mkscope("resolve-polcy: enforce\n*.lab.example.com\n")
        self.assertIn("resolve-polcy", str(cm.exception))

    def test_bad_directive_value_is_a_parse_error(self):
        with self.assertRaises(S.ScopeParseError):
            mkscope("resolve-policy: sometimes\n")

    def test_malformed_cidr_is_a_parse_error(self):
        with self.assertRaises(S.ScopeParseError):
            mkscope("192.0.2.0/33\n")

    def test_grammar_round_trip(self):
        text = (
            "resolve-policy: enforce\n"
            "*.lab.example.com\n"
            "lab.example.com\n"
            "192.0.2.0/24\n"
            "10.10.0.5\n"
            "!status.lab.example.com\n"
            "!198.51.100.0/24\n"
        )
        once = mkscope(text)
        twice = mkscope(once.to_text())
        self.assertEqual(once.to_text(), twice.to_text())
        self.assertEqual(once.sha256(), twice.sha256())

    def test_sha256_is_stable_and_content_addressed(self):
        a = mkscope("*.lab.example.com\n192.0.2.0/24\n")
        b = mkscope("# different comment\n*.lab.example.com\n192.0.2.0/24\n")
        c = mkscope("*.lab.example.com\n")
        self.assertEqual(a.sha256(), b.sha256())
        self.assertNotEqual(a.sha256(), c.sha256())


# --------------------------------------------------------------------------
# resolve-policy derivation (§5.2)
# --------------------------------------------------------------------------
class TestPolicyDerivation(unittest.TestCase):
    def test_scope_with_only_names_derives_warn(self):
        self.assertEqual(mkscope("*.lab.example.com\nacme.com\n").policy, "warn")

    def test_scope_with_a_cidr_derives_enforce(self):
        self.assertEqual(mkscope("*.lab.example.com\n192.0.2.0/24\n").policy, "enforce")

    def test_scope_with_a_literal_address_derives_enforce(self):
        self.assertEqual(mkscope("*.lab.example.com\n10.10.0.5\n").policy, "enforce")

    def test_explicit_directive_overrides_derivation(self):
        self.assertEqual(mkscope("resolve-policy: warn\n192.0.2.0/24\n").policy, "warn")
        self.assertEqual(mkscope("resolve-policy: off\n*.lab.example.com\n").policy, "off")

    def test_deny_addresses_alone_do_not_derive_enforce(self):
        # A deny CIDR authorizes nothing; it cannot upgrade the policy.
        self.assertEqual(mkscope("*.lab.example.com\n!198.51.100.0/24\n").policy, "warn")

    def test_empty_scope_file_derives_warn_and_authorizes_nothing(self):
        sc = mkscope("")
        self.assertEqual(sc.policy, "warn")
        v = S.authorize("anything.example.com", ["192.0.2.7"], sc)
        self.assertFalse(v.allowed)


# --------------------------------------------------------------------------
# authorize() — the §15 case table
# --------------------------------------------------------------------------
LAB = "resolve-policy: enforce\n*.lab.example.com\n192.0.2.0/24\n"


class TestAuthorize(unittest.TestCase):
    def test_name_and_address_both_authorized(self):
        v = S.authorize("web.lab.example.com", ["192.0.2.10"], mkscope(LAB))
        self.assertTrue(v.allowed)
        self.assertFalse(v.unverified_addr)
        self.assertIsNone(v.proposal)
        self.assertEqual(v.policy, "enforce")

    def test_cname_to_third_party_address_is_denied(self):
        # status.lab.example.com CNAMEs to a status vendor outside the lab range.
        v = S.authorize("status.lab.example.com", ["23.185.0.4"], mkscope(LAB))
        self.assertFalse(v.allowed)
        self.assertIn("23.185.0.4", v.reason)
        self.assertIsNotNone(v.proposal)

    def test_one_stray_address_denies_under_enforce(self):
        v = S.authorize("web.lab.example.com", ["192.0.2.10", "23.185.0.4"], mkscope(LAB))
        self.assertFalse(v.allowed)
        self.assertIn("23.185.0.4", v.reason)
        self.assertNotIn("192.0.2.10", v.reason)

    def test_same_stray_is_allowed_and_flagged_under_warn(self):
        sc = mkscope("resolve-policy: warn\n*.lab.example.com\n192.0.2.0/24\n")
        v = S.authorize("web.lab.example.com", ["192.0.2.10", "23.185.0.4"], sc)
        self.assertTrue(v.allowed)
        self.assertTrue(v.unverified_addr)
        self.assertIsNotNone(v.proposal)
        self.assertEqual(v.policy, "warn")

    def test_explicit_deny_beats_a_broad_allow(self):
        sc = mkscope(LAB + "!status.lab.example.com\n")
        v = S.authorize("status.lab.example.com", ["192.0.2.10"], sc)
        self.assertFalse(v.allowed)
        self.assertIn("deny", v.reason.lower())
        self.assertIsNone(v.proposal)  # never propose widening around a deny

    def test_deny_on_address_while_name_allows(self):
        sc = mkscope(LAB + "!192.0.2.99\n")
        v = S.authorize("web.lab.example.com", ["192.0.2.99"], sc)
        self.assertFalse(v.allowed)
        self.assertIn("deny", v.reason.lower())

    def test_deny_cidr_beats_allow_cidr_regardless_of_order(self):
        sc = mkscope("!192.0.2.0/25\n*.lab.example.com\n192.0.2.0/24\n")
        self.assertFalse(S.authorize("web.lab.example.com", ["192.0.2.5"], sc).allowed)
        self.assertTrue(S.authorize("web.lab.example.com", ["192.0.2.200"], sc).allowed)

    def test_name_not_in_scope_is_denied_with_a_proposal(self):
        v = S.authorize("acme.com", ["192.0.2.10"], mkscope(LAB))
        self.assertFalse(v.allowed)
        self.assertIn("not in scope", v.reason)
        self.assertIn("acme.com", v.proposal)

    def test_glob_suffix_does_not_match_the_bare_apex(self):
        sc = mkscope("resolve-policy: enforce\n*.lab.example.com\n192.0.2.0/24\n")
        self.assertFalse(S.authorize("lab.example.com", ["192.0.2.10"], sc).allowed)

    def test_apex_matches_when_listed_explicitly(self):
        sc = mkscope("resolve-policy: enforce\n*.lab.example.com\nlab.example.com\n192.0.2.0/24\n")
        self.assertTrue(S.authorize("lab.example.com", ["192.0.2.10"], sc).allowed)

    def test_glob_matches_nested_subdomains(self):
        sc = mkscope(LAB)
        self.assertTrue(S.authorize("a.b.lab.example.com", ["192.0.2.10"], sc).allowed)

    def test_glob_does_not_match_a_sibling_suffix(self):
        # *.lab.example.com must not authorize evil-lab.example.com
        sc = mkscope(LAB)
        self.assertFalse(S.authorize("evil-lab.example.com", ["192.0.2.10"], sc).allowed)

    def test_hostname_match_is_case_insensitive_and_trailing_dot_tolerant(self):
        sc = mkscope(LAB)
        self.assertTrue(S.authorize("WEB.Lab.Example.COM.", ["192.0.2.10"], sc).allowed)

    def test_literal_address_entry_authorizes_that_address(self):
        sc = mkscope("resolve-policy: enforce\nbastion.internal\n10.10.0.5\n")
        self.assertTrue(S.authorize("bastion.internal", ["10.10.0.5"], sc).allowed)
        self.assertFalse(S.authorize("bastion.internal", ["10.10.0.6"], sc).allowed)

    def test_ipv6_literal_and_cidr(self):
        sc = mkscope("resolve-policy: enforce\n*.lab.example.com\n2001:db8::/32\n")
        self.assertTrue(S.authorize("web.lab.example.com", ["2001:db8::1"], sc).allowed)
        self.assertFalse(S.authorize("web.lab.example.com", ["2001:dba::1"], sc).allowed)

    def test_bare_ip_target_authorizes_via_address_entries(self):
        sc = mkscope("resolve-policy: enforce\n192.0.2.0/24\n")
        self.assertTrue(S.authorize("192.0.2.10", ["192.0.2.10"], sc).allowed)
        self.assertFalse(S.authorize("198.51.100.10", ["198.51.100.10"], sc).allowed)

    def test_wildcard_dns_host_is_still_name_authorized(self):
        # authorize() does name+address only. Wildcard-DNS detection is dnsx's
        # job (§16); pinning that boundary here so it is never smuggled in.
        sc = mkscope(LAB)
        v = S.authorize("nonexistent-a7f3zz.lab.example.com", ["192.0.2.10"], sc)
        self.assertTrue(v.allowed)

    def test_empty_address_list_under_enforce_is_denied(self):
        # Nothing resolved => nothing was address-verified => fail closed.
        v = S.authorize("web.lab.example.com", [], mkscope(LAB))
        self.assertFalse(v.allowed)

    def test_policy_off_skips_the_address_check_but_flags_it(self):
        sc = mkscope("resolve-policy: off\n*.lab.example.com\n192.0.2.0/24\n")
        v = S.authorize("web.lab.example.com", ["23.185.0.4"], sc)
        self.assertTrue(v.allowed)
        self.assertTrue(v.unverified_addr)
        self.assertEqual(v.policy, "off")

    def test_policy_off_still_honours_deny(self):
        sc = mkscope("resolve-policy: off\n*.lab.example.com\n!bad.lab.example.com\n")
        self.assertFalse(S.authorize("bad.lab.example.com", ["192.0.2.10"], sc).allowed)


# --------------------------------------------------------------------------
# active-invasive hard block (§5.2, §5.4)
# --------------------------------------------------------------------------
class TestInvasive(unittest.TestCase):
    def test_invasive_allowed_under_enforce(self):
        v = S.authorize("web.lab.example.com", ["192.0.2.10"], mkscope(LAB),
                        scope_class="active-invasive")
        self.assertTrue(v.allowed)

    def test_invasive_hard_blocked_under_warn(self):
        sc = mkscope("resolve-policy: warn\n*.lab.example.com\n192.0.2.0/24\n")
        v = S.authorize("web.lab.example.com", ["192.0.2.10"], sc,
                        scope_class="active-invasive")
        self.assertFalse(v.allowed)
        self.assertIn("invasive", v.reason.lower())

    def test_invasive_hard_blocked_under_off(self):
        sc = mkscope("resolve-policy: off\n*.lab.example.com\n192.0.2.0/24\n")
        v = S.authorize("web.lab.example.com", ["192.0.2.10"], sc,
                        scope_class="active-invasive")
        self.assertFalse(v.allowed)
        self.assertIn("invasive", v.reason.lower())

    def test_local_scope_class_needs_no_target(self):
        v = S.authorize(None, [], mkscope(LAB), scope_class="local")
        self.assertTrue(v.allowed)

    def test_unknown_scope_class_is_rejected(self):
        with self.assertRaises(ValueError):
            S.authorize("web.lab.example.com", ["192.0.2.10"], mkscope(LAB),
                        scope_class="active-super-invasive")


# --------------------------------------------------------------------------
# Engagement scope overlay (§5.7)
# --------------------------------------------------------------------------
class TestOverlay(unittest.TestCase):
    def test_overlay_name_extends_the_global_allowlist(self):
        sc = mkscope("192.0.2.0/24\n", overlay="lab-a7f3.lab.internal\n")
        self.assertTrue(S.authorize("lab-a7f3.lab.internal", ["192.0.2.10"], sc).allowed)

    def test_overlay_cannot_reauthorize_a_globally_denied_name(self):
        sc = mkscope("192.0.2.0/24\n!lab-a7f3.lab.internal\n",
                     overlay="lab-a7f3.lab.internal\n")
        v = S.authorize("lab-a7f3.lab.internal", ["192.0.2.10"], sc)
        self.assertFalse(v.allowed)
        self.assertIn("deny", v.reason.lower())

    def test_overlay_deny_beats_a_global_allow(self):
        sc = mkscope(LAB, overlay="!web.lab.example.com\n")
        self.assertFalse(S.authorize("web.lab.example.com", ["192.0.2.10"], sc).allowed)

    def test_durable_cidr_plus_ephemeral_names_derives_enforce(self):
        # The §5.7 configuration the design assumes.
        sc = mkscope("192.0.2.0/24\n", overlay="lab-a7f3.lab.internal\n")
        self.assertEqual(sc.policy, "enforce")

    def test_sha256_covers_the_overlay(self):
        base = "192.0.2.0/24\n"
        a = mkscope(base, overlay="lab-a7f3.lab.internal\n")
        b = mkscope(base, overlay="lab-b881.lab.internal\n")
        self.assertNotEqual(a.sha256(), b.sha256())


# --------------------------------------------------------------------------
# Proposals (§5.1) — ready-to-paste, never auto-applied
# --------------------------------------------------------------------------
class TestProposals(unittest.TestCase):
    def test_name_proposal_is_a_scope_command(self):
        v = S.authorize("acme.com", ["192.0.2.10"], mkscope(LAB))
        self.assertIn("/scope", v.proposal)
        self.assertIn("acme.com", v.proposal)

    def test_cidr_proposal_names_the_stray_addresses(self):
        v = S.authorize("web.lab.example.com", ["23.185.0.4"], mkscope(LAB))
        self.assertIn("23.185.0.4", v.proposal)

    def test_verdict_is_immutable(self):
        v = S.authorize("web.lab.example.com", ["192.0.2.10"], mkscope(LAB))
        with self.assertRaises(Exception):
            v.allowed = False


if __name__ == "__main__":
    unittest.main()
