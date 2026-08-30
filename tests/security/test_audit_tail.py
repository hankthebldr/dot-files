#!/usr/bin/env python3
"""A removed audit tail must not verify clean (§8).

A hash chain detects edits to history and is blind to removal of its end: drop
the last N lines and the surviving prefix verifies perfectly. Re-chain the
survivors from genesis and it still does. §8 says "the absence [of a refusal
log] is itself a finding" — silent truncation is precisely how that absence
gets manufactured, and `claw sec audit verify` reported OK for both.

The chain's expected length is now anchored in `audit.head` beside it.

What this is worth, stated plainly: anyone who can truncate `audit.jsonl` can
also rewrite `audit.head`. The marker raises tampering from "delete lines" to
"delete lines and keep a second file consistent", and it catches the realistic
accidents outright — a crash mid-append, ENOSPC, a partial sync. A real anchor
would have to live off this filesystem. These tests pin the behaviour, not a
claim of tamper-proofing.
"""
import json
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "scripts" / "security"))

import registry as R  # noqa: E402
import scope as S  # noqa: E402


class AuditCase(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.ctx = R.Engagement(root=self.tmp, run_id="t",
                                scope=S.Scope.from_text("*.lab.internal\n"),
                                registry={})
        for i in range(5):
            R.audit_event(self.ctx, event="phase", detail=f"record {i}")

    def records(self):
        return [l for l in self.ctx.audit_path.read_text().splitlines() if l.strip()]

    def rewrite(self, lines):
        self.ctx.audit_path.write_text("".join(l + "\n" for l in lines))

    @property
    def head(self):
        return self.tmp / R.AUDIT_HEAD_FILE


class TestIntactChain(AuditCase):
    def test_an_untouched_chain_verifies(self):
        ok, detail = R.verify_audit(self.ctx)
        self.assertTrue(ok, detail)
        self.assertIn("5 record(s) verified", detail)

    def test_the_head_marker_tracks_the_last_record(self):
        marker = json.loads(self.head.read_text())
        last = json.loads(self.records()[-1])
        self.assertEqual(marker["seq"], last["seq"])
        self.assertEqual(marker["record_hash"], last["record_hash"])

    def test_appending_advances_the_marker(self):
        R.audit_event(self.ctx, event="phase", detail="one more")
        self.assertEqual(json.loads(self.head.read_text())["seq"], 6)
        self.assertTrue(R.verify_audit(self.ctx)[0])


class TestTailRemoval(AuditCase):
    def test_a_truncated_tail_is_caught(self):
        self.rewrite(self.records()[:3])
        ok, detail = R.verify_audit(self.ctx)
        self.assertFalse(ok)
        self.assertIn("missing from the tail", detail)

    def test_the_report_names_how_many_records_vanished(self):
        self.rewrite(self.records()[:3])
        self.assertIn("2 record(s) missing", R.verify_audit(self.ctx)[1])

    def test_a_chain_rebuilt_from_genesis_is_still_caught(self):
        # The strongest version of the attack: re-hash the survivors so the
        # walk itself is flawless. Only the length gives it away.
        kept = [json.loads(l) for l in self.records()[:3]]
        prev = "genesis"
        for i, rec in enumerate(kept, start=1):
            rec.pop("record_hash", None)
            rec["seq"], rec["prev_hash"] = i, prev
            rec["record_hash"] = R._record_hash(rec, prev)
            prev = rec["record_hash"]
        self.rewrite([json.dumps(r, sort_keys=True, ensure_ascii=False) for r in kept])

        walk_ok = True
        try:
            walk_ok = R.verify_audit(self.ctx)[0]
        finally:
            self.assertFalse(walk_ok, "a rechained prefix must not verify")

    def test_removing_every_record_is_caught(self):
        self.rewrite([])
        self.assertFalse(R.verify_audit(self.ctx)[0])


class TestMarkerHandling(AuditCase):
    def test_an_absent_marker_verifies_but_says_the_tail_is_unanchored(self):
        # Engagements written before the marker existed must still verify.
        self.head.unlink()
        ok, detail = R.verify_audit(self.ctx)
        self.assertTrue(ok)
        self.assertIn("unanchored", detail)

    def test_an_unreadable_marker_is_reported_not_ignored(self):
        self.head.write_text("{not json")
        ok, detail = R.verify_audit(self.ctx)
        self.assertFalse(ok)
        self.assertIn("head marker", detail)

    def test_a_marker_naming_the_wrong_hash_is_caught(self):
        marker = json.loads(self.head.read_text())
        marker["record_hash"] = "0" * 64
        self.head.write_text(json.dumps(marker))
        self.assertFalse(R.verify_audit(self.ctx)[0])

    def test_no_temp_marker_is_left_behind(self):
        self.assertEqual(list(self.tmp.glob("audit.head.tmp.*")), [])


class TestEditsStillCaught(AuditCase):
    """The pre-existing guarantees must survive the change."""

    def test_a_content_edit_breaks_the_chain(self):
        recs = self.records()
        rec = json.loads(recs[2])
        rec["detail"] = "tampered"
        recs[2] = json.dumps(rec, sort_keys=True, ensure_ascii=False)
        self.rewrite(recs)
        self.assertFalse(R.verify_audit(self.ctx)[0])

    def test_reordering_breaks_the_chain(self):
        recs = self.records()
        recs[1], recs[2] = recs[2], recs[1]
        self.rewrite(recs)
        self.assertFalse(R.verify_audit(self.ctx)[0])

    def test_deleting_a_middle_record_breaks_the_chain(self):
        recs = self.records()
        del recs[2]
        self.rewrite(recs)
        self.assertFalse(R.verify_audit(self.ctx)[0])


if __name__ == "__main__":
    unittest.main()
