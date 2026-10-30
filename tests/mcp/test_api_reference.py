"""Keep the handwritten HIR reference aligned with the exported native enums."""

import ast
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
REFERENCE = ROOT / "modules/cjmcp/api/loupe.pyi"


def python_type(native):
    """Translate the value-type grammar used by the exported HIR payloads."""
    native = native.strip()
    if native.startswith("?"):
        return python_type(native[1:]) + " | None"
    if native.startswith("Array<") and native.endswith(">"):
        return "list[" + python_type(native[6:-1]) + "]"
    return {"String": "str", "Int64": "int", "Bool": "bool"}.get(native, native)


def hir_enums():
    registration = (ROOT / "modules/cjmcp/src/python_types.cj").read_text()
    exported = set(re.findall(r'\("(\w+)",', registration))
    enums = {}
    for path in sorted((ROOT / "modules/loupe/src/hir").glob("*.cj")):
        source = path.read_text()
        for match in re.finditer(r"^public enum (\w+)[^{]*\{(.*?)^}", source, re.M | re.S):
            name, body = match.groups()
            if name in exported:
                enums[name] = {
                    variant: [python_type(ty) for ty in payload.split(",")] if payload else []
                    for variant, payload in re.findall(r"^    \| (\w+)(?:\((.*)\))?", body, re.M)
                }
    return enums


class ApiReferenceTest(unittest.TestCase):
    def setUp(self):
        self.tree = ast.parse(REFERENCE.read_text())
        declarations = [node for node in self.tree.body if isinstance(node, ast.ClassDef)]
        self.classes = {node.name: node for node in declarations}
        self.assertEqual(len(self.classes), len(declarations), "duplicate reference class")

    def test_all_exported_hir_variants_and_payloads(self):
        enums = hir_enums()
        self.assertIn("Expr", enums)
        self.assertIn("TyKind", enums)
        for name, variants in enums.items():
            with self.subTest(enum=name):
                self.assertIn(name, set(self.classes))
                enum = self.classes[name]
                attributes = {
                    node.target.id: ast.unparse(node.annotation)
                    for node in enum.body if isinstance(node, ast.AnnAssign)
                }
                self.assertEqual(set(attributes), set(variants))
                kind = next(node for node in enum.body if isinstance(node, ast.FunctionDef) and node.name == "kind")
                self.assertEqual(ast.unparse(kind.returns), "str")
                for variant, payload in variants.items():
                    with self.subTest(enum=name, variant=variant):
                        helper = f"_{name}{variant}"
                        self.assertEqual(attributes[variant], f"ClassVar[type[{helper}]]")
                        declaration = self.classes[helper]
                        self.assertEqual([ast.unparse(base) for base in declaration.bases], [name])
                        methods = {node.name: node for node in declaration.body if isinstance(node, ast.FunctionDef)}
                        constructor = methods.pop("__init__")
                        self.assertEqual([arg.arg for arg in constructor.args.args], ["self"] + [f"field{i}" for i in range(len(payload))])
                        self.assertEqual([ast.unparse(arg.annotation) for arg in constructor.args.args[1:]], payload)
                        self.assertEqual(set(methods), {f"field{i}" for i in range(len(payload))})
                        for i, ty in enumerate(payload):
                            field = methods[f"field{i}"]
                            self.assertEqual(ast.unparse(field.returns), ty)
                            self.assertEqual([ast.unparse(d) for d in field.decorator_list], ["property"])
                        match_args = next(node for node in declaration.body if isinstance(node, ast.AnnAssign) and node.target.id == "__match_args__")
                        self.assertEqual(ast.literal_eval(match_args.value), tuple(f"field{i}" for i in range(len(payload))))

    def test_text_range_len_is_read_only_byte_length(self):
        native = (ROOT / "modules/ginkgo/src/text_range.cj").read_text()
        self.assertRegex(native, r"public prop len: Int64\s*\{\s*get\(\)\s*\{\s*end - start")
        length = next(node for node in self.classes["TextRange"].body if isinstance(node, ast.FunctionDef) and node.name == "len")
        self.assertEqual([ast.unparse(d) for d in length.decorator_list], ["property"])
        self.assertEqual(ast.unparse(length.returns), "int")
        self.assertIn("UTF-8", ast.get_docstring(length))

    def test_annotations_resolve(self):
        declared = set(self.classes) | {"Any", "ClassVar", "str", "int", "bool", "list", "tuple", "type"}
        annotations = []
        for node in ast.walk(self.tree):
            if isinstance(node, (ast.arg, ast.AnnAssign)) and node.annotation:
                annotations.append(node.annotation)
            elif isinstance(node, ast.FunctionDef) and node.returns:
                annotations.append(node.returns)
        for annotation in annotations:
            for node in ast.walk(annotation):
                if isinstance(node, ast.Name):
                    self.assertIn(node.id, declared)
