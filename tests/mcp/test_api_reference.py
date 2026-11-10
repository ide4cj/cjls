"""Check the supplied reference independently of a running MCP server."""
import ast
import builtins
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

    def test_signature_types_have_python_names(self):
        trees = [ast.parse(path.read_text(encoding="utf-8")) for path in sorted(ROOT.rglob("*.pyi"))]
        known = set(dir(builtins))
        known.update(node.name for tree in trees for node in ast.walk(tree)
                     if isinstance(node, ast.ClassDef))
        known.update(alias.asname or alias.name for tree in trees for node in tree.body
                     if isinstance(node, ast.ImportFrom) for alias in node.names)
        for tree in trees:
            for node in ast.walk(tree):
                if not isinstance(node, ast.FunctionDef):
                    continue
                annotations = [arg.annotation for arg in
                               node.args.posonlyargs + node.args.args + node.args.kwonlyargs
                               if arg.annotation is not None]
                if node.returns is not None:
                    annotations.append(node.returns)
                names = {part.id for annotation in annotations for part in ast.walk(annotation)
                         if isinstance(part, ast.Name)}
                with self.subTest(member=node.name):
                    self.assertFalse(names - known, names - known)

    def test_macro_only_and_ignored_members_are_not_advertised(self):
        cases = [
            ("cjformat/options.pyi", "SimpleIf", {"fromToml"}, set()),
            ("cjformat/options.pyi", "FormatOptions", {"fromToml"}, {"__init__"}),
            ("loupe.hir/body.pyi", "BodySourceMap",
             {"__init__", "exprAt", "patAt", "localAt", "typeAt"}, {"exprAtSource"}),
            ("loupe.hir/body.pyi", "LocalAnnotation", {"__init__"}, set()),
            ("loupe/semantic_syntax.pyi", "SemanticSyntaxPointer", {"__init__"}, set()),
            ("loupe/semantic_syntax.pyi", "SemanticSyntaxError", {"__init__"}, {"message"}),
            ("cjmcp/analysis.pyi", "AnalysisRevision", set(), {"substituteType"}),
            ("loupe.db/project.pyi", "Cfg", set(), {"__init__"}),
        ]
        for path, name, hidden, visible in cases:
            tree = ast.parse((ROOT / path).read_text(encoding="utf-8"))
            cls = next(node for node in tree.body if isinstance(node, ast.ClassDef) and node.name == name)
            members = {node.name for node in cls.body if isinstance(node, ast.FunctionDef)}
            with self.subTest(type=name):
                self.assertFalse(members & hidden, members & hidden)
                self.assertTrue(visible <= members, visible - members)
        for path in sorted(ROOT.rglob("*.pyi")):
            tree = ast.parse(path.read_text(encoding="utf-8"))
            self.assertFalse(any(isinstance(node, ast.ClassDef) and node.name.startswith("CalcaFields_")
                                 for node in tree.body), path)

    def test_hidden_members_are_not_advertised(self):
        tree = ast.parse((ROOT / "cjmcp/python.pyi").read_text(encoding="utf-8"))
        workspace = next(node for node in tree.body if isinstance(node, ast.ClassDef) and node.name == "Workspace")
        members = {node.name for node in workspace.body if isinstance(node, ast.FunctionDef)}
        self.assertNotIn("bind", members)
        apply = next(node for node in workspace.body if isinstance(node, ast.FunctionDef) and node.name == "applyChange")
        self.assertIn("revision", ast.get_docstring(apply))


if __name__ == "__main__":
    unittest.main()
