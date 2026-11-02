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
