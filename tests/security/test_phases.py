#!/usr/bin/env python3
"""Flow execution, resumability and the safety regression test (spec §11, §15).

The assertion this file exists for is the last one: across a full run, no
gated tool ever received a target that the gate did not emit. Everything else
here — resume rules, the feedback loop, the kill switch — protects that
property across time rather than within a single invocation.

The whole flow runs offline against fixture binaries.
"""
import json
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).resolve().parent / "fixtures"
sys.path.insert(0, str(REPO / "scripts" / "security"))

import lint as L  # noqa: E402
import phases as P  # noqa: E402
import registry as R  # noqa: E402
import scope as S  # noqa: E402

LAB = "resolve-policy: enforce\n*.lab.internal\n192.0.2.0/24\n"


class FlowCase(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="claw-flow-"))
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self._path = os.environ["PATH"]
        os.environ["PATH"] = f"{FIXTURES / 'bin'}{os.pathsep}{self._path}"
        self.addCleanup(lambda: os.environ.__setitem__("PATH", self._path))
        R._IDENTITY_CACHE.clear()

        self.registry = L.load_registry(FIXTURES / "registry.yaml")
        self.flow = L.load_flows(FIXTURES / "flows")[0]
        self.ctx = R.Engagement(root=self.tmp, run_id="run-flow-0001",
                                scope=S.Scope.from_text(LAB), registry=self.registry)

    def run_flow(self, seed="lab.internal", **kw):
        return P.run(self.flow, self.ctx, seed=[seed], **kw)


class TestSafetyRegression(FlowCase):
    """The test the whole design exists to pass."""

    def test_no_gated_tool_ever_receives_a_target_the_gate_did_not_emit(self):
        report = self.run_flow()
        authorized = {h for h, _ in P.read_targets(self.ctx, "authorized_host")}
        self.assertTrue(authorized)
        gated = [c for c in report.invocations
                 if self.registry[c.tool]["scope_class"] in S.GATED_CLASSES]
        self.assertTrue(gated, "no gated tool ran; the test would prove nothing")
        for call in gated:
            for host in call.targets:
                self.assertIn(host, authorized, f"{call.tool} was handed {host}")

    def test_an_out_of_scope_discovery_is_denied_at_the_gate(self):
        self.run_flow()
        denied = {row["host"] for row in P.read_rows(self.ctx.root / "gate" / "denied.jsonl")}
        self.assertIn("leaked-asset.example.org", denied)

    def test_a_denied_host_appears_in_no_downstream_artifact(self):
        self.run_flow()
        for path in (self.ctx.root / "scans").glob("fx-probe*.jsonl"):
            self.assertNotIn("leaked-asset.example.org", path.read_text())

    def test_a_lab_name_that_resolves_off_scope_is_denied(self):
        # old.lab.internal CNAMEs to a CDN address. Authorization is on the
        # resolved address, so the name being in scope is not enough (§5.1).
        self.run_flow()
        denied = {row["host"] for row in P.read_rows(self.ctx.root / "gate" / "denied.jsonl")}
        self.assertIn("old.lab.internal", denied)

    def test_authorized_hosts_are_exactly_the_in_scope_ones(self):
        self.run_flow()
        authorized = {h for h, _ in P.read_targets(self.ctx, "authorized_host")}
        self.assertEqual(authorized, {"web.lab.internal", "api.lab.internal"})


class TestFlowMechanics(FlowCase):
    def test_every_phase_runs_and_is_recorded(self):
        report = self.run_flow()
        self.assertEqual([p.id for p in report.phases], [0, 1, 2, 3, 4, 5, 6])
        self.assertTrue(all(p.completed_at for p in report.phases))

    def test_findings_reach_the_final_phase(self):
        self.run_flow()
        findings = list(P.read_rows(*(self.ctx.root / "scans").glob("fx-signal*.jsonl")))
        self.assertTrue(findings)

    def test_tainted_output_is_marked_all_the_way_through(self):
        self.run_flow()
        rows = list(P.read_rows(*(self.ctx.root / "scans").glob("fx-probe*.jsonl")))
        self.assertTrue(all(r["tainted"] for r in rows))

    def test_an_injection_payload_is_carried_as_inert_data(self):
        self.run_flow()
        titles = [r.get("title", "") for r in
                  P.read_rows(*(self.ctx.root / "scans").glob("fx-probe*.jsonl"))]
        self.assertTrue(any("Ignore prior instructions" in t for t in titles))
        self.assertFalse(any("\x1b" in t for t in titles))

    def test_the_scope_snapshot_is_written_at_phase_zero(self):
        self.run_flow()
        snapshot = self.ctx.root / "scope.snapshot"
        self.assertTrue(snapshot.exists())
        self.assertEqual(S.Scope.from_text(snapshot.read_text()).sha256(),
                         self.ctx.scope.sha256())

    def test_dry_run_builds_argv_and_writes_no_scan_artifact(self):
        report = self.run_flow(dry_run=True)
        self.assertTrue(all(c.argv for c in report.invocations))
        self.assertFalse(list((self.ctx.root / "scans").glob("fx-probe*.jsonl")))

    def test_dry_run_still_records_an_audit_trail(self):
        self.run_flow(dry_run=True)
        ok, _ = R.verify_audit(self.ctx)
        self.assertTrue(ok)
        self.assertTrue(self.ctx.audit_path.exists())

    def test_the_audit_chain_survives_a_full_run(self):
        self.run_flow()
        ok, detail = R.verify_audit(self.ctx)
        self.assertTrue(ok, detail)

    def test_report_counts_denials(self):
        self.assertGreater(self.run_flow().denied, 0)


class TestFeedbackLoop(FlowCase):
    def test_feedback_returns_to_the_gate_and_converges(self):
        report = self.run_flow()
        self.assertLessEqual(report.gate_iterations, P.MAX_GATE_ITERATIONS)
        self.assertGreaterEqual(report.gate_iterations, 1)

    def test_the_gate_artifact_is_append_only_and_idempotent(self):
        self.run_flow()
        before = (self.ctx.root / "gate" / "authorized.jsonl").read_text()
        P.gate_hosts(self.ctx, [("web.lab.internal", ["192.0.2.10"])])
        after = (self.ctx.root / "gate" / "authorized.jsonl").read_text()
        self.assertEqual(before, after)

    def test_a_host_denied_once_is_not_re_authorized_on_re_entry(self):
        self.run_flow()
        P.gate_hosts(self.ctx, [("leaked-asset.example.org", ["198.51.100.7"])])
        authorized = {h for h, _ in P.read_targets(self.ctx, "authorized_host")}
        self.assertNotIn("leaked-asset.example.org", authorized)


class TestKillSwitch(FlowCase):
    def test_halt_stops_the_run_at_the_next_phase(self):
        R.halt(self.ctx, reason="operator stop")
        report = self.run_flow()
        self.assertTrue(report.halted)
        self.assertFalse(list((self.ctx.root / "scans").glob("fx-probe*.jsonl")))

    def test_halt_is_recorded_in_the_report(self):
        R.halt(self.ctx, reason="operator stop")
        self.assertIn("halt", self.run_flow().status.lower())


class TestResume(FlowCase):
    def test_a_completed_phase_is_skipped_on_resume(self):
        self.run_flow()
        second = self.run_flow()
        self.assertTrue(all(p.skipped for p in second.phases))

    def test_redo_forces_a_phase_to_run_again(self):
        self.run_flow()
        second = self.run_flow(redo=[4])
        by_id = {p.id: p for p in second.phases}
        self.assertFalse(by_id[4].skipped)

    def test_resume_is_permitted_when_the_overlay_only_gains_entries(self):
        # On-demand lab assets churn constantly; additive overlay growth must
        # not block resumption, because every new host still traverses the gate.
        self.run_flow()
        self.ctx.scope = S.Scope.from_text(LAB, overlay_text="lab-a7f3.lab.internal\n")
        report = self.run_flow()
        self.assertFalse(report.blocked, report.status)

    def test_resume_is_blocked_when_an_allow_entry_is_removed(self):
        self.run_flow()
        self.ctx.scope = S.Scope.from_text("resolve-policy: enforce\n192.0.2.0/24\n")
        report = self.run_flow()
        self.assertTrue(report.blocked)
        self.assertIn("--redo", report.status)

    def test_resume_is_blocked_when_a_deny_entry_is_added(self):
        self.run_flow()
        self.ctx.scope = S.Scope.from_text(LAB + "!api.lab.internal\n")
        self.assertTrue(self.run_flow().blocked)

    def test_resume_is_blocked_when_the_policy_changes(self):
        self.run_flow()
        self.ctx.scope = S.Scope.from_text("resolve-policy: warn\n*.lab.internal\n192.0.2.0/24\n")
        self.assertTrue(self.run_flow().blocked)

    def test_the_structural_verdict_is_recorded_in_state(self):
        self.run_flow()
        state = json.loads((self.ctx.root / "state" / "3.done").read_text())
        for key in ("scope_sha256", "policy", "completed_at", "allow_names"):
            self.assertIn(key, state)


if __name__ == "__main__":
    unittest.main()
