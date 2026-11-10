"""Check the supplied reference independently of a running MCP server."""
import ast
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2] / "modules/cjmcp/api_docs"


class ApiReferenceTest(unittest.TestCase):
    def test_files_are_valid_python_syntax(self):
        files = sorted(ROOT.rglob("*.pyi"))
        self.assertTrue(files)
        for path in files:
            with self.subTest(path=path.relative_to(ROOT)):
                ast.parse(path.read_text(encoding="utf-8"), filename=str(path))

    def test_type_links_have_supplied_targets(self):
        for path in sorted(ROOT.rglob("*.pyi")):
            for target in re.findall(r"see '([^']+\.pyi)'", path.read_text(encoding="utf-8")):
                with self.subTest(path=path.relative_to(ROOT), target=target):
                    self.assertTrue((ROOT / target).is_file())

    def test_hidden_members_are_not_advertised(self):
        tree = ast.parse((ROOT / "cjmcp/python.pyi").read_text(encoding="utf-8"))
        workspace = next(node for node in tree.body if isinstance(node, ast.ClassDef) and node.name == "Workspace")
        members = {node.name for node in workspace.body if isinstance(node, ast.FunctionDef)}
        self.assertNotIn("bind", members)
        apply = next(node for node in workspace.body if isinstance(node, ast.FunctionDef) and node.name == "applyChange")
        self.assertIn("revision", ast.get_docstring(apply))


if __name__ == "__main__":
    unittest.main()
