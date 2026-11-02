"""Graph contract independent of native proxy allocation and workspace loading."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("call_audit", Path(__file__).resolve().parents[2] / "modules/cjmcp/api/call_audit.py")
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class ShortestCallsTest(unittest.TestCase):
    def test_shortest_per_target_cycles_and_unknown(self):
        graph = {"root": ["long", "short"], "long": ["middle"], "middle": ["target"],
                 "short": ["target", "other"], "target": ["root"], "other": []}
        def successors(node):
            return [(dest, (node, dest)) for dest in graph[node]], (["unavailable-body"] if node == "other" else [])
        paths, gaps, visited = audit.shortest_paths("root", successors, lambda node: node in {"target", "other"})
        self.assertEqual(dict(paths)["target"], [("root", "short"), ("short", "target")])
        self.assertEqual(dict(paths)["other"], [("root", "short"), ("short", "other")])
        self.assertEqual(gaps, ["unavailable-body"])
        self.assertEqual(visited, 6)

    def test_empty_incomplete_graph_is_not_negative_evidence(self):
        paths, gaps, _ = audit.shortest_paths("root", lambda _: ([], ["functional-value"]), lambda _: False)
        self.assertEqual(paths, [])
        self.assertEqual(gaps, ["functional-value"])

    def test_budget_is_explicit_and_does_not_drop_known_paths(self):
        paths, gaps, visited = audit.shortest_paths("root", lambda node: ([("a", "edge"), ("b", "edge")], []), lambda node: node == "a", limit=2)
        self.assertEqual(paths, [("a", ["edge"])])
        self.assertTrue(any(gap["reason"] == "node-limit" for gap in gaps))
        self.assertEqual(visited, 2)


class NativeCallAuditTest(unittest.TestCase):
    def test_real_cjmcp_reports_each_target_and_ignores_unused_lambda(self):
        import json
        import os
        import subprocess
        import tempfile
        import sys
        if not sys.platform.startswith("linux"):
            self.skipTest("embedded CPython experiment supports native Linux")
        root = Path(__file__).resolve().parents[2]
        binary = os.environ.get("CJMCP_BIN", str(root / "target/release/bin/cjmcp"))
        code = (root / "modules/cjmcp/api/call_audit.py").read_text() + "\nresult = audit(workspace)\n"
        messages = [
            {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
                "protocolVersion": "2025-11-25", "capabilities": {},
                "clientInfo": {"name": "audit-test", "version": "1"}}},
            {"jsonrpc": "2.0", "method": "notifications/initialized"},
            {"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {
                "name": "runPython", "arguments": {"code": code}}}]
        # Preparation may create build metadata: keep the checked-in fixture immutable.
        import shutil
        with tempfile.TemporaryDirectory(prefix="cjmcp-call-audit-") as directory:
            shutil.copytree(root / "tests/mcp/call_audit_fixture", Path(directory) / "fixture")
            process = subprocess.run([binary, "--dir", str(Path(directory) / "fixture")],
                                     input="".join(json.dumps(message) + "\n" for message in messages),
                                     text=True, capture_output=True, timeout=180,
                                     env={**os.environ, "cjHeapSize": "2GB"})
        self.assertEqual(process.returncode, 0, process.stderr)
        response = next(json.loads(line) for line in process.stdout.splitlines() if json.loads(line).get("id") == 2)
        payload = response["result"]["structuredContent"]
        self.assertIsNone(payload["error"], payload)
        report = payload["result"]
        self.assertEqual(report["problems"], [])
        self.assertTrue(report["has_expanded_macros"])
        self.assertEqual(len(report["reports"]), 1)
        query = report["reports"][0]
        self.assertEqual(query["status"], "reachable")
        self.assertEqual({finding["target"]["name"] for finding in query["findings"]}, {"getProcessId", "getCommand"})
        for finding in query["findings"]:
            self.assertEqual(finding["distance"], 2)
            self.assertEqual(finding["certainty"], "resolved")
            self.assertEqual(finding["edges"][0]["callee"]["name"], "via")
            self.assertEqual(finding["target"]["package"], "std.env")
            self.assertTrue(all(edge["site"]["line"] > 0 for edge in finding["edges"]))
        self.assertFalse(query["coverage_complete"])
        self.assertEqual(query["unlisted_targets"], "unknown")
