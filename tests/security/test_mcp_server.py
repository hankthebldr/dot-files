#!/usr/bin/env python3
"""MCP adapter (spec §4.2, §5.6, §7).

Protocol translation and nothing else. The adapter holds no authorization
logic — it calls registry.invoke() like every other caller, because a gate in
the adapter is a gate with a way around it.

The property this file pins hardest: an active-invasive tool is *absent* from
tools/list unless the engagement opted in. Absence is strictly stronger than
refusal, because a refusal is a signal to retry differently.
"""
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).resolve().parent / "fixtures"
sys.path.insert(0, str(REPO / "scripts" / "security"))

import lint as L  # noqa: E402
import mcp_server as M  # noqa: E402
import registry as R  # noqa: E402
import scope as S  # noqa: E402


class ServerCase(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="claw-mcp-"))
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.registry = L.load_registry()
        self.ctx = R.Engagement(root=self.tmp, run_id="mcp-test",
                                scope=S.Scope.from_text("*.lab.internal\n192.0.2.0/24\n"),
                                registry=self.registry)
        self.server = M.Server(self.ctx)

    def rpc(self, method, params=None, mid=1):
        return self.server.handle({"jsonrpc": "2.0", "id": mid,
                                   "method": method, "params": params or {}})


class TestProtocol(ServerCase):
    def test_initialize_declares_tools_capability(self):
        out = self.rpc("initialize")
        self.assertIn("capabilities", out["result"])
        self.assertIn("tools", out["result"]["capabilities"])

    def test_initialize_names_the_server(self):
        self.assertIn("claw", self.rpc("initialize")["result"]["serverInfo"]["name"])

    def test_unknown_method_returns_a_jsonrpc_error(self):
        out = self.rpc("no/such/method")
        self.assertEqual(out["error"]["code"], -32601)

    def test_notifications_produce_no_response(self):
        self.assertIsNone(self.server.handle(
            {"jsonrpc": "2.0", "method": "notifications/initialized"}))

    def test_a_malformed_message_does_not_crash_the_server(self):
        out = self.server.handle({"jsonrpc": "2.0", "id": 9})
        self.assertIn("error", out)

    def test_responses_echo_the_request_id(self):
        self.assertEqual(self.rpc("tools/list", mid=42)["id"], 42)


class TestToolsList(ServerCase):
    def tools(self, ctx=None):
        server = M.Server(ctx) if ctx else self.server
        return {t["name"]: t for t in
                server.handle({"jsonrpc": "2.0", "id": 1, "method": "tools/list",
                               "params": {}})["result"]["tools"]}

    def test_registry_tools_are_exposed(self):
        self.assertIn("httpx", self.tools())

    def test_the_artifact_primitives_are_exposed(self):
        listed = self.tools()
        self.assertIn("query", listed)
        self.assertIn("stats", listed)

    def test_descriptions_come_from_the_registry(self):
        self.assertIn("fingerprint", self.tools()["httpx"]["description"].lower())

    def test_model_sourced_params_appear_in_the_schema(self):
        props = self.tools()["httpx"]["inputSchema"]["properties"]
        self.assertIn("threads", props)
        self.assertEqual(props["threads"]["type"], "integer")

    def test_numeric_bounds_are_carried_into_the_schema(self):
        threads = self.tools()["httpx"]["inputSchema"]["properties"]["threads"]
        self.assertEqual(threads["minimum"], 1)
        self.assertEqual(threads["maximum"], 150)

    def test_enum_values_are_carried_into_the_schema(self):
        severity = self.tools()["nuclei"]["inputSchema"]["properties"]["severity"]
        self.assertIn("critical", severity["enum"])

    def test_artifact_params_are_exposed_as_references(self):
        props = self.tools()["httpx"]["inputSchema"]["properties"]
        self.assertIn("input_file", props)
        self.assertIn("artifact", props["input_file"]["description"].lower())

    def test_config_sourced_params_are_not_model_settable(self):
        # The egress rule at the protocol boundary: a destination read from
        # config must not become a field the model can fill.
        self.assertNotIn("provider_config",
                         self.tools()["notify"]["inputSchema"]["properties"])

    def test_required_lists_params_without_defaults(self):
        self.assertIn("input_file", self.tools()["httpx"]["inputSchema"]["required"])

    def test_a_param_with_a_default_is_not_required(self):
        self.assertNotIn("threads", self.tools()["httpx"]["inputSchema"]["required"])


class TestInvasiveVisibility(ServerCase):
    def listed(self, ctx):
        return {t["name"] for t in
                M.Server(ctx).handle({"jsonrpc": "2.0", "id": 1,
                                      "method": "tools/list", "params": {}})["result"]["tools"]}

    def make_invasive(self):
        spec = dict(self.registry["nuclei"])
        spec["scope_class"] = "active-invasive"
        self.registry["sqlmap"] = spec

    def test_an_invasive_tool_is_absent_without_opt_in(self):
        self.make_invasive()
        self.assertNotIn("sqlmap", self.listed(self.ctx))

    def test_an_invasive_tool_appears_with_opt_in(self):
        self.make_invasive()
        self.ctx.allow_invasive = True
        self.assertIn("sqlmap", self.listed(self.ctx))

    def test_calling_an_unlisted_invasive_tool_is_still_refused(self):
        # Absence is the control; the executor is the backstop.
        self.make_invasive()
        out = self.rpc("tools/call", {"name": "sqlmap", "arguments": {}})
        self.assertTrue(out.get("result", {}).get("isError") or "error" in out)


class TestToolsCall(ServerCase):
    def setUp(self):
        super().setUp()
        self.gate = self.tmp / "gate" / "authorized.jsonl"
        self.gate.parent.mkdir(parents=True)
        self.gate.write_text(json.dumps(
            {"host": "web.lab.internal", "addrs": ["192.0.2.10"]}) + "\n")

    def call(self, name, args):
        return self.rpc("tools/call", {"name": name, "arguments": args})

    def test_an_unknown_tool_is_an_error_not_a_crash(self):
        out = self.call("not-a-tool", {})
        self.assertTrue(out.get("result", {}).get("isError") or "error" in out)

    def test_a_denied_call_returns_the_structured_status(self):
        forged = self.tmp / "forged.jsonl"
        forged.write_text(json.dumps({"host": "victim.example.org"}) + "\n")
        out = self.call("httpx", {"input_file": str(forged)})
        payload = json.loads(out["result"]["content"][0]["text"])
        self.assertEqual(payload["status"], "denied_scope")
        self.assertIn("proposal", payload)

    def test_a_missing_tool_binary_is_reported_structurally(self):
        spec = dict(self.registry["httpx"])
        spec["binary"] = "definitely-not-installed-xyz"
        self.registry["ghosttool"] = spec
        out = self.call("ghosttool", {"input_file": str(self.gate)})
        payload = json.loads(out["result"]["content"][0]["text"])
        self.assertIn(payload["status"], ("tool_missing", "tool_identity"))

    def test_query_is_routed_to_the_artifact_layer(self):
        art = self.tmp / "rows.jsonl"
        art.write_text(json.dumps({"url": "https://a", "status_code": 200}) + "\n")
        out = self.call("query", {"artifact": str(art),
                                  "where": [{"field": "status_code", "op": "eq", "value": 200}]})
        payload = json.loads(out["result"]["content"][0]["text"])
        self.assertEqual(payload["count"], 1)

    def test_stats_is_routed_to_the_artifact_layer(self):
        art = self.tmp / "rows.jsonl"
        art.write_text("".join(json.dumps({"status_code": c}) + "\n" for c in (200, 200, 404)))
        out = self.call("stats", {"artifact": str(art), "group_by": "status_code"})
        payload = json.loads(out["result"]["content"][0]["text"])
        self.assertEqual(payload["groups"][0]["count"], 2)

    def test_a_bad_query_returns_an_error_not_an_exception(self):
        art = self.tmp / "rows.jsonl"
        art.write_text(json.dumps({"a": 1}) + "\n")
        out = self.call("query", {"artifact": str(art), "where": "a == 1"})
        self.assertTrue(out.get("result", {}).get("isError") or "error" in out)

    def test_every_call_is_audited(self):
        forged = self.tmp / "forged.jsonl"
        forged.write_text(json.dumps({"host": "victim.example.org"}) + "\n")
        self.call("httpx", {"input_file": str(forged)})
        self.assertTrue(self.ctx.audit_path.exists())

    def test_the_adapter_contains_no_authorization_logic(self):
        source = (REPO / "scripts" / "security" / "mcp_server.py").read_text()
        self.assertNotIn("authorize(", source)
        self.assertNotIn("scope.txt", source)


if __name__ == "__main__":
    unittest.main()
