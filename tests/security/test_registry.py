#!/usr/bin/env python3
"""The executor (spec §4, §8, §9, §10).

The gate lives here and nowhere else. An MCP `tools/call` never touches the
Bash tool, so a harness whose gate sits in the adapter is a clean bypass around
`pre_tool_use.py`. Putting `authorize()` inside `invoke()` means every adapter
— MCP, Ollama, and any future one — inherits identical default-deny with no
route around it. These tests are what proves that.

No network: tools are fixture scripts on a temporary PATH.
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

import registry as R  # noqa: E402
import scope as S  # noqa: E402

LAB_SCOPE = "resolve-policy: enforce\n*.lab.example.com\n192.0.2.0/24\n"


def spec(**over):
    base = {
        "description": "A fixture tool that emits rows for executor tests only.",
        "binary": "fake-emit",
        "scope_class": "active",
        "consumes": ["authorized_host"],
        "emits": ["endpoint"],
        "packages": {"kali": "fake-emit"},
        "verify": ["fake-emit", "-version"],
        "expect": "projectdiscovery",
        "argv": ["-list", "{input_file}", "-count", "{count}"],
        "params": {
            "input_file": {"type": "artifact", "of": "authorized_host", "source": "artifact"},
            "count": {"type": "integer", "default": 3, "min": 1, "max": 100, "source": "model"},
        },
        "parser": "jsonl",
        "taint_fields": ["url", "title"],
        "rate": {"per_target_rps": 100, "max_concurrency": 4},
        "timeout": 10,
    }
    base.update(over)
    return base


class HarnessCase(unittest.TestCase):
    """Engagement on a temp dir, fixture tools on PATH, no network."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="claw-sec-test-"))
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self._path = os.environ["PATH"]
        os.environ["PATH"] = f"{FIXTURES / 'bin'}{os.pathsep}{self._path}"
        self.addCleanup(lambda: os.environ.__setitem__("PATH", self._path))

        self.reg = {"faketool": spec()}
        self.ctx = R.Engagement(
            root=self.tmp,
            run_id="run-test-0001",
            scope=S.Scope.from_text(LAB_SCOPE),
            registry=self.reg,
        )
        self.authorized = self.write_artifact("gate/authorized.jsonl", [
            {"host": "web.lab.example.com", "addrs": ["192.0.2.10"]},
            {"host": "api.lab.example.com", "addrs": ["192.0.2.11"]},
        ])

    def write_artifact(self, rel, rows):
        p = self.tmp / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text("".join(json.dumps(r) + "\n" for r in rows), encoding="utf-8")
        return p

    def invoke(self, tool="faketool", **params):
        params.setdefault("input_file", str(self.authorized))
        return R.invoke(tool, params, self.ctx)


# --------------------------------------------------------------------------
class TestArgvBuilding(HarnessCase):
    def test_argv_is_a_list_with_slots_filled(self):
        argv = R.build_argv("faketool", spec(), {"input_file": "/tmp/x", "count": 5})
        self.assertEqual(argv, ["fake-emit", "-list", "/tmp/x", "-count", "5"])

    def test_defaults_are_applied(self):
        argv = R.build_argv("faketool", spec(), {"input_file": "/tmp/x"})
        self.assertIn("3", argv)

    def test_integer_below_minimum_is_rejected(self):
        with self.assertRaises(R.ParamError):
            R.build_argv("faketool", spec(), {"input_file": "/tmp/x", "count": 0})

    def test_integer_above_maximum_is_rejected(self):
        with self.assertRaises(R.ParamError):
            R.build_argv("faketool", spec(), {"input_file": "/tmp/x", "count": 10_000})

    def test_non_integer_for_integer_param_is_rejected(self):
        with self.assertRaises(R.ParamError):
            R.build_argv("faketool", spec(), {"input_file": "/tmp/x", "count": "3; rm -rf /"})

    def test_undeclared_param_is_rejected(self):
        with self.assertRaises(R.ParamError):
            R.build_argv("faketool", spec(), {"input_file": "/tmp/x", "sneaky": "value"})

    def test_enum_value_outside_the_declared_set_is_rejected(self):
        s = spec(argv=["-severity", "{severity}"],
                 params={"severity": {"type": "enum", "values": ["low", "high"],
                                      "default": "low", "source": "model"}})
        with self.assertRaises(R.ParamError):
            R.build_argv("faketool", s, {"severity": "critical"})

    def test_missing_param_with_no_default_is_rejected(self):
        with self.assertRaises(R.ParamError):
            R.build_argv("faketool", spec(), {})

    def test_every_argv_element_is_a_string(self):
        argv = R.build_argv("faketool", spec(), {"input_file": "/tmp/x", "count": 5})
        self.assertTrue(all(isinstance(a, str) for a in argv))

    def test_the_executor_never_uses_a_shell(self):
        source = (REPO / "scripts" / "security" / "registry.py").read_text()
        self.assertNotIn("shell=True", source)
        self.assertNotIn("os.system", source)


# --------------------------------------------------------------------------
class TestGate(HarnessCase):
    """No gated tool may ever receive a target the gate did not pass."""

    def test_authorized_targets_run(self):
        r = self.invoke()
        self.assertEqual(r.status, R.Status.OK)

    def test_an_out_of_scope_target_in_the_input_denies_the_whole_invocation(self):
        poisoned = self.write_artifact("gate/poisoned.jsonl", [
            {"host": "web.lab.example.com", "addrs": ["192.0.2.10"]},
            {"host": "victim.example.org", "addrs": ["198.51.100.7"]},
        ])
        r = self.invoke(input_file=str(poisoned))
        self.assertEqual(r.status, R.Status.DENIED_SCOPE)
        self.assertIn("victim.example.org", r.reason)
        self.assertIsNotNone(r.proposal)

    def test_a_denied_invocation_executes_nothing(self):
        poisoned = self.write_artifact("gate/poisoned.jsonl",
                                       [{"host": "victim.example.org", "addrs": ["198.51.100.7"]}])
        r = self.invoke(input_file=str(poisoned))
        self.assertIsNone(r.artifact)
        self.assertEqual(r.count, 0)

    def test_a_target_whose_address_left_scope_is_denied(self):
        # In-scope name, but it now resolves to a CDN. §5.1.
        drifted = self.write_artifact("gate/drifted.jsonl",
                                      [{"host": "cdn.lab.example.com", "addrs": ["23.185.0.4"]}])
        r = self.invoke(input_file=str(drifted))
        self.assertEqual(r.status, R.Status.DENIED_SCOPE)

    def test_invasive_tool_is_denied_without_engagement_opt_in(self):
        self.reg["faketool"] = spec(scope_class="active-invasive")
        r = self.invoke()
        self.assertEqual(r.status, R.Status.DENIED_INVASIVE)

    def test_invasive_tool_runs_with_opt_in(self):
        self.reg["faketool"] = spec(scope_class="active-invasive")
        self.ctx.allow_invasive = True
        self.assertEqual(self.invoke().status, R.Status.OK)

    def test_disclosing_passive_tool_is_denied_by_default(self):
        self.reg["faketool"] = spec(scope_class="passive", consumes=["domain"],
                                    discloses_target=True)
        self.reg["faketool"]["params"]["input_file"]["of"] = "domain"
        r = self.invoke()
        self.assertEqual(r.status, R.Status.DENIED_DISCLOSURE)

    def test_a_downstream_row_is_authorized_against_the_gate_record(self):
        # endpoint/url rows name a host but carry no addresses; the addresses
        # come from what the gate itself recorded.
        gate = self.write_artifact("gate/authorized.jsonl", [
            {"host": "web.lab.example.com", "addrs": ["192.0.2.10"]},
        ])
        self.assertTrue(gate.exists())
        endpoints = self.write_artifact("scans/endpoints.jsonl", [
            {"url": "https://web.lab.example.com/admin", "host": "web.lab.example.com"},
        ])
        self.reg["faketool"] = spec(consumes=["endpoint"])
        self.reg["faketool"]["params"]["input_file"]["of"] = "endpoint"
        self.assertEqual(self.invoke(input_file=str(endpoints)).status, R.Status.OK)

    def test_a_fabricated_downstream_row_cannot_smuggle_a_target(self):
        # A host the gate never saw resolves to nothing, and under `enforce`
        # nothing to verify is a denial.
        self.write_artifact("gate/authorized.jsonl", [
            {"host": "web.lab.example.com", "addrs": ["192.0.2.10"]},
        ])
        forged = self.write_artifact("scans/forged.jsonl", [
            {"url": "https://victim.example.org/", "host": "victim.example.org"},
        ])
        self.reg["faketool"] = spec(consumes=["endpoint"])
        self.reg["faketool"]["params"]["input_file"]["of"] = "endpoint"
        r = self.invoke(input_file=str(forged))
        self.assertEqual(r.status, R.Status.DENIED_SCOPE)
        self.assertIn("victim.example.org", r.reason)

    def test_passive_tool_is_not_target_gated(self):
        # Passive sources touch third parties, not the target (§5.4).
        self.reg["faketool"] = spec(scope_class="passive", consumes=["domain"])
        self.reg["faketool"]["params"]["input_file"]["of"] = "domain"
        anything = self.write_artifact("passive/in.jsonl", [{"host": "acme.com"}])
        self.assertEqual(self.invoke(input_file=str(anything)).status, R.Status.OK)


# --------------------------------------------------------------------------
class TestExecution(HarnessCase):
    def test_rows_are_written_to_an_artifact_not_returned(self):
        r = self.invoke(count=50)
        self.assertEqual(r.count, 50)
        self.assertTrue(r.artifact.exists())
        self.assertLessEqual(len(r.sample), 5)
        self.assertTrue(r.truncated)

    def test_sample_rows_are_sanitised_and_taint_marked(self):
        r = self.invoke()
        self.assertTrue(all(row["tainted"] for row in r.sample))

    def test_zero_rows_is_empty_not_ok(self):
        # Half the Kali traps fail by producing zero rows that read as a clean
        # target. `empty` must never be confused with `ok`.
        self.reg["faketool"] = spec(binary="fake-empty", verify=["fake-empty", "-version"])
        self.assertEqual(self.invoke().status, R.Status.EMPTY)

    def test_nonzero_exit_with_no_rows_is_reported_with_stderr(self):
        self.reg["faketool"] = spec(binary="fake-fail", verify=["fake-fail", "-version"])
        r = self.invoke()
        self.assertEqual(r.status, R.Status.MALFORMED)
        self.assertIn("connection refused", r.stderr_tail)

    def test_missing_binary_is_reported_as_tool_missing(self):
        self.reg["faketool"] = spec(binary="definitely-not-installed-xyz")
        r = self.invoke()
        self.assertEqual(r.status, R.Status.TOOL_MISSING)
        self.assertIn("definitely-not-installed-xyz", r.reason)

    def test_wrong_binary_on_path_is_reported_as_tool_identity(self):
        # `command -v` reported four tools present that were a Python library
        # and three git aliases. Presence is not identity (§13).
        self.reg["faketool"] = spec(binary="fake-imposter",
                                    verify=["fake-imposter", "-version"])
        r = self.invoke()
        self.assertEqual(r.status, R.Status.TOOL_IDENTITY)

    def test_timeout_kills_the_tool_and_retains_partial_output(self):
        self.reg["faketool"] = spec(binary="fake-slow", verify=["fake-slow", "-version"],
                                    timeout=1)
        r = self.invoke()
        self.assertEqual(r.status, R.Status.TIMEOUT)
        self.assertLess(r.duration_ms, 15_000)

    def test_dry_run_builds_argv_but_executes_nothing(self):
        self.ctx.dry_run = True
        r = self.invoke()
        self.assertEqual(r.status, R.Status.OK)
        self.assertIsNone(r.artifact)
        self.assertIn("-count", r.argv)

    def test_dry_run_still_enforces_the_gate(self):
        self.ctx.dry_run = True
        poisoned = self.write_artifact("gate/poisoned.jsonl",
                                       [{"host": "victim.example.org", "addrs": ["198.51.100.7"]}])
        self.assertEqual(self.invoke(input_file=str(poisoned)).status, R.Status.DENIED_SCOPE)

    def test_unknown_tool_is_rejected(self):
        with self.assertRaises(KeyError):
            R.invoke("no-such-tool", {}, self.ctx)


# --------------------------------------------------------------------------
class TestKillSwitchAndRate(HarnessCase):
    def test_halt_file_stops_every_invocation(self):
        R.halt(self.ctx, reason="operator stop")
        r = self.invoke()
        self.assertEqual(r.status, R.Status.HALTED)

    def test_halt_cannot_be_cleared_through_invoke(self):
        R.halt(self.ctx, reason="operator stop")
        self.invoke()
        self.assertTrue(R.is_halted(self.ctx))

    def test_resume_clears_the_halt(self):
        R.halt(self.ctx, reason="stop")
        R.resume(self.ctx)
        self.assertEqual(self.invoke().status, R.Status.OK)

    def test_rate_limit_returns_retry_after(self):
        self.reg["faketool"] = spec(rate={"per_target_rps": 1, "max_concurrency": 1})
        first = self.invoke()
        self.assertEqual(first.status, R.Status.OK)
        second = self.invoke()
        self.assertEqual(second.status, R.Status.RATE_LIMITED)
        self.assertGreater(second.retry_after_ms, 0)

    def test_rate_buckets_key_on_address_not_hostname(self):
        # 40 vhosts on one address share one bucket (§10).
        self.reg["faketool"] = spec(rate={"per_target_rps": 1, "max_concurrency": 1})
        vhosts = self.write_artifact("gate/vhosts.jsonl", [
            {"host": "a.lab.example.com", "addrs": ["192.0.2.10"]},
            {"host": "b.lab.example.com", "addrs": ["192.0.2.10"]},
        ])
        self.assertEqual(self.invoke(input_file=str(vhosts)).status, R.Status.OK)
        self.assertEqual(self.invoke(input_file=str(vhosts)).status, R.Status.RATE_LIMITED)

    def test_budget_status_when_the_artifact_is_too_large_to_read(self):
        self.ctx.budget_rows = 10
        r = self.invoke(count=50)
        self.assertEqual(r.status, R.Status.BUDGET)
        self.assertTrue(r.artifact.exists())
        self.assertEqual(r.count, 50)


# --------------------------------------------------------------------------
class TestAudit(HarnessCase):
    def records(self):
        return [json.loads(l) for l in
                (self.tmp / "audit.jsonl").read_text().splitlines() if l.strip()]

    def test_every_invocation_is_recorded(self):
        self.invoke()
        self.assertEqual(len(self.records()), 1)

    def test_a_denial_is_recorded_with_equal_weight(self):
        # The refusal log is evidence of a working control; its absence is a finding.
        poisoned = self.write_artifact("gate/poisoned.jsonl",
                                       [{"host": "victim.example.org", "addrs": ["198.51.100.7"]}])
        self.invoke(input_file=str(poisoned))
        rec = self.records()[0]
        self.assertEqual(rec["verdict"], "deny")
        self.assertEqual(rec["status"], "denied_scope")

    def test_record_carries_provenance_fields(self):
        self.invoke()
        rec = self.records()[0]
        for key in ("ts", "run_id", "seq", "tool", "policy", "scope_sha256",
                    "argv_sha256", "artifact_sha256", "prev_hash", "record_hash"):
            self.assertIn(key, rec)

    def test_records_are_hash_chained(self):
        self.invoke()
        self.invoke()
        a, b = self.records()
        self.assertEqual(b["prev_hash"], a["record_hash"])

    def test_sequence_numbers_increment(self):
        self.invoke()
        self.invoke()
        self.assertEqual([r["seq"] for r in self.records()], [1, 2])

    def test_verify_accepts_an_untouched_chain(self):
        self.invoke()
        self.invoke()
        ok, detail = R.verify_audit(self.ctx)
        self.assertTrue(ok, detail)

    def test_editing_history_breaks_the_chain(self):
        self.invoke()
        self.invoke()
        path = self.tmp / "audit.jsonl"
        recs = self.records()
        recs[0]["tool"] = "something-else"
        path.write_text("".join(json.dumps(r) + "\n" for r in recs), encoding="utf-8")
        ok, detail = R.verify_audit(self.ctx)
        self.assertFalse(ok)
        self.assertIn("1", detail)

    def test_deleting_a_record_breaks_the_chain(self):
        self.invoke()
        self.invoke()
        path = self.tmp / "audit.jsonl"
        recs = self.records()
        path.write_text(json.dumps(recs[1]) + "\n", encoding="utf-8")
        ok, _ = R.verify_audit(self.ctx)
        self.assertFalse(ok)

    def test_appending_is_normal(self):
        self.invoke()
        ok_before, _ = R.verify_audit(self.ctx)
        self.invoke()
        ok_after, _ = R.verify_audit(self.ctx)
        self.assertTrue(ok_before and ok_after)

    def test_audit_records_the_policy_in_force(self):
        self.invoke()
        self.assertEqual(self.records()[0]["policy"], "enforce")

    def test_audit_records_unverified_addresses_under_warn(self):
        self.ctx.scope = S.Scope.from_text("*.lab.example.com\n")
        self.invoke()
        rec = self.records()[0]
        self.assertEqual(rec["policy"], "warn")
        self.assertTrue(rec["unverified_addr"])

    def test_the_model_cannot_suppress_a_record(self):
        # There is no parameter, flag or context field that disables auditing.
        source = (REPO / "scripts" / "security" / "registry.py").read_text()
        self.assertNotIn("skip_audit", source)
        self.assertNotIn("no_audit", source)


if __name__ == "__main__":
    unittest.main()
