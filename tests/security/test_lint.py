#!/usr/bin/env python3
"""Registry and flow lint rules (spec §3.1, §6.2, §6.4, §6.6).

These are the rules that make the gate structural rather than remembered:
a tool author cannot opt in or out, their declared input type decides.
"""
import sys
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "scripts" / "security"))

import lint as L  # noqa: E402


def tool(**over):
    """A minimal valid gated tool entry; override one field per test."""
    base = {
        "description": "Crawl an authorized endpoint and enumerate routes.",
        "binary": "katana",
        "scope_class": "active",
        "consumes": ["endpoint"],
        "emits": ["url", "param"],
        "packages": {"kali": "katana"},
        "verify": ["katana", "-version"],
        "expect": "projectdiscovery",
        "argv": ["-list", "{input_file}", "-depth", "{depth}"],
        "params": {
            "input_file": {"type": "artifact", "of": "endpoint", "source": "artifact"},
            "depth": {"type": "integer", "default": 3, "min": 1, "max": 6, "source": "model"},
        },
        "parser": "jsonl",
        "taint_fields": ["url", "title"],
        "timeout": 900,
    }
    base.update(over)
    return {"katana": base}


def errs(registry):
    return L.lint_registry(registry)


class TestSchema(unittest.TestCase):
    def test_a_well_formed_entry_passes(self):
        self.assertEqual(errs(tool()), [])

    def test_missing_description_fails(self):
        r = tool()
        del r["katana"]["description"]
        self.assertTrue(any("description" in e for e in errs(r)))

    def test_unknown_scope_class_fails(self):
        self.assertTrue(any("scope_class" in e for e in errs(tool(scope_class="aggressive"))))

    def test_unknown_artifact_type_fails(self):
        self.assertTrue(any("vibes" in e for e in errs(tool(emits=["vibes"]))))

    def test_unknown_parser_fails(self):
        self.assertTrue(any("parser" in e for e in errs(tool(parser="magic"))))

    def test_py_parser_prefix_is_accepted(self):
        self.assertEqual(errs(tool(parser="py:my_parser")), [])

    def test_missing_identity_assertion_fails(self):
        r = tool()
        del r["katana"]["expect"]
        self.assertTrue(any("expect" in e for e in errs(r)))


class TestTypeRule(unittest.TestCase):
    """§6.2 — a gated tool is structurally unable to receive an unauthorized target."""

    def test_gated_tool_consuming_hostname_fails(self):
        self.assertTrue(any("hostname" in e for e in errs(tool(consumes=["hostname"]))))

    def test_gated_tool_consuming_host_fails(self):
        self.assertTrue(any("host" in e for e in errs(tool(consumes=["host"]))))

    def test_gated_tool_consuming_domain_fails(self):
        self.assertTrue(any("domain" in e for e in errs(tool(consumes=["domain"]))))

    def test_gated_tool_consuming_authorized_host_passes(self):
        r = tool(consumes=["authorized_host"])
        r["katana"]["params"]["input_file"]["of"] = "authorized_host"
        self.assertEqual(errs(r), [])

    def test_passive_tool_may_consume_domain(self):
        r = tool(scope_class="passive", consumes=["domain"])
        r["katana"]["params"]["input_file"]["of"] = "domain"
        self.assertEqual(errs(r), [])

    def test_artifact_param_of_type_must_be_a_declared_input(self):
        r = tool(consumes=["endpoint"])
        r["katana"]["params"]["input_file"]["of"] = "url"
        self.assertTrue(any("input_file" in e for e in errs(r)))

    def test_active_light_is_gated_too(self):
        self.assertTrue(any("hostname" in e for e in errs(
            tool(scope_class="active-light", consumes=["hostname"]))))

    def test_invasive_is_gated_too(self):
        self.assertTrue(any("hostname" in e for e in errs(
            tool(scope_class="active-invasive", consumes=["hostname"]))))


class TestEgressRule(unittest.TestCase):
    """§3.1 — no destination may come from model output."""

    def test_model_sourced_url_param_fails(self):
        r = tool()
        r["katana"]["argv"] += ["-webhook", "{callback}"]
        r["katana"]["params"]["callback"] = {"type": "url", "source": "model"}
        self.assertTrue(any("callback" in e and "egress" in e.lower() for e in errs(r)))

    def test_model_sourced_hostname_param_fails(self):
        r = tool()
        r["katana"]["argv"] += ["-server", "{iserver}"]
        r["katana"]["params"]["iserver"] = {"type": "hostname", "source": "model"}
        self.assertTrue(any("iserver" in e for e in errs(r)))

    def test_model_sourced_path_param_fails(self):
        r = tool()
        r["katana"]["argv"] += ["-o", "{outfile}"]
        r["katana"]["params"]["outfile"] = {"type": "path", "source": "model"}
        self.assertTrue(any("outfile" in e for e in errs(r)))

    def test_config_sourced_url_param_passes(self):
        r = tool()
        r["katana"]["argv"] += ["-webhook", "{callback}"]
        r["katana"]["params"]["callback"] = {"type": "url", "source": "config"}
        self.assertEqual(errs(r), [])

    def test_artifact_sourced_url_param_passes(self):
        r = tool()
        r["katana"]["argv"] += ["-u", "{target}"]
        r["katana"]["params"]["target"] = {"type": "url", "source": "artifact", "of": "endpoint"}
        self.assertEqual(errs(r), [])


class TestArgvSlots(unittest.TestCase):
    """argv is a fixed template with typed slots — never an interpolated string."""

    def test_undeclared_slot_fails(self):
        self.assertTrue(any("{rate}" in e for e in errs(
            tool(argv=["-list", "{input_file}", "-rate", "{rate}"]))))

    def test_declared_param_absent_from_argv_fails(self):
        self.assertTrue(any("depth" in e for e in errs(tool(argv=["-list", "{input_file}"]))))

    def test_argv_element_containing_a_shell_metacharacter_fails(self):
        self.assertTrue(any("shell" in e.lower() for e in errs(
            tool(argv=["-list", "{input_file} | tee /tmp/x", "-depth", "{depth}"]))))

    def test_argv_slot_must_be_the_whole_element(self):
        # "-depth={depth}" would require string interpolation; slots are discrete argv elements.
        self.assertTrue(any("depth" in e for e in errs(
            tool(argv=["-list", "{input_file}", "-depth={depth}"]))))


class TestTaint(unittest.TestCase):
    def test_taint_field_must_be_declared_for_target_controlled_output(self):
        # A gated tool that emits findings/urls without declaring taint_fields
        # is asserting its output is trustworthy. It is not (§3.2).
        r = tool()
        r["katana"].pop("taint_fields", None)
        self.assertTrue(any("taint" in e.lower() for e in errs(r)))

    def test_declared_taint_fields_pass(self):
        self.assertEqual(errs(tool(taint_fields=["url", "title"])), [])

    def test_local_tool_needs_no_taint_fields(self):
        r = tool(scope_class="local", consumes=["finding"], emits=["finding"])
        r["katana"]["params"]["input_file"]["of"] = "finding"
        r["katana"].pop("taint_fields")
        self.assertEqual(errs(r), [])


FLOW = {
    "name": "webrecon",
    "description": "Authorized web application attack-surface discovery",
    "phases": [
        {"id": 0, "name": "init", "scope_class": "local", "emits": ["domain"]},
        {"id": 1, "name": "passive", "tools": ["subfinder"], "consumes": ["domain"],
         "emits": ["hostname"]},
        {"id": 2, "name": "resolve", "tools": ["dnsx"], "consumes": ["hostname"],
         "emits": ["host"]},
        {"id": 3, "name": "gate", "gate": True, "consumes": ["host"],
         "emits": ["authorized_host"]},
        {"id": 4, "name": "live", "tools": ["httpx"], "consumes": ["authorized_host"],
         "emits": ["endpoint"], "feeds_back_to": 3},
        {"id": 5, "name": "signal", "tools": ["nuclei"], "consumes": ["endpoint"],
         "emits": ["finding"]},
    ],
}


def flow(**over):
    import copy
    f = copy.deepcopy(FLOW)
    f.update(over)
    return f


class TestFlowLint(unittest.TestCase):
    def test_a_well_formed_flow_passes(self):
        self.assertEqual(L.lint_flow(flow()), [])

    def test_consumed_type_with_no_ancestor_producer_fails(self):
        f = flow()
        f["phases"][1]["consumes"] = ["cert"]
        self.assertTrue(any("cert" in e for e in L.lint_flow(f)))

    def test_exactly_one_gate_phase_is_required(self):
        f = flow()
        f["phases"][2]["gate"] = True
        self.assertTrue(any("gate" in e for e in L.lint_flow(f)))

    def test_zero_gate_phases_fails(self):
        f = flow()
        del f["phases"][3]["gate"]
        self.assertTrue(any("gate" in e for e in L.lint_flow(f)))

    def test_only_the_gate_may_emit_authorized_host(self):
        f = flow()
        f["phases"][1]["emits"] = ["hostname", "authorized_host"]
        self.assertTrue(any("authorized_host" in e for e in L.lint_flow(f)))

    def test_feeds_back_to_must_target_the_gate(self):
        f = flow()
        f["phases"][4]["feeds_back_to"] = 2
        self.assertTrue(any("feeds_back_to" in e for e in L.lint_flow(f)))

    def test_phase_ids_must_be_ordered_and_unique(self):
        f = flow()
        f["phases"][4]["id"] = 1
        self.assertTrue(any("id" in e for e in L.lint_flow(f)))


class TestShippedConfig(unittest.TestCase):
    """The real registry and flows must pass their own lint."""

    def test_shipped_registry_lints_clean(self):
        self.assertEqual(L.lint_registry(L.load_registry()), [])

    def test_shipped_flows_lint_clean(self):
        registry = L.load_registry()
        found = 0
        for f in L.load_flows():
            found += 1
            self.assertEqual(L.lint_flow(f, registry=registry), [], f"flow {f.get('name')}")
        self.assertGreater(found, 0, "no flows shipped")

    def test_tier0_chain_is_present(self):
        r = L.load_registry()
        for name in ("subfinder", "dnsx", "tlsx", "naabu", "httpx", "katana", "nuclei"):
            self.assertIn(name, r)

    def test_no_gated_tool_in_the_shipped_registry_consumes_an_ungated_type(self):
        r = L.load_registry()
        gated = {"active-light", "active", "active-invasive"}
        for name, spec in r.items():
            if spec["scope_class"] in gated:
                for t in spec["consumes"]:
                    self.assertIn(t, L.GATED_INPUT_TYPES, f"{name} consumes {t}")

    def test_every_shipped_tool_declares_a_kali_package(self):
        for name, spec in L.load_registry().items():
            self.assertIn("kali", spec.get("packages", {}), name)


if __name__ == "__main__":
    unittest.main()
