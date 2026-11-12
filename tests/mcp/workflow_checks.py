"""Regressions for observed agent discovery, edit and reference mistakes."""

import tempfile
from pathlib import Path


class WorkflowChecks:
    def test_exact_discovery_and_annotation_edits(self):
        with tempfile.TemporaryDirectory(prefix="cjmcp-edit-recipe-") as directory:
            root = Path(directory)
            (root / "src").mkdir()
            (root / "cjpm.toml").write_text(
                '[package]\nname = "sample"\nversion = "0.1.0"\noutput-type = "static"\n')
            source = """package sample
import std.unittest.*
import std.unittest.testmacro.*
// Кириллица checks byte offsets before the decorated declaration.
@Test
class Example {
    @TestCase
    func target() { @Expect(1, 1) }
    @TestCase
    func targetExtra() { @Expect(2, 2) }
}
"""
            (root / "src/example_test.cj").write_text(source)
            response = self._api_docs_script(self.workflow_binary(), root, """
a = workspace.analysis()
path = 'src/example_test.cj'
matches = exact_symbols(a, [path, path], 'target')
assert len(matches) == 1
assert exact_symbols(a, [path], 'TARGET') == []
assert exact_symbols(a, [path], 'tget') == []
symbol = matches[0][1]
span = declaration_range(a, path, symbol.selectionRange, 'FuncDecl')
before = a.text(path)
data = before.encode('utf-8')
assert data[span.start:span.end].startswith(b'@TestCase')
assert data[span.start:span.end].count(b'@TestCase') == 1
assert span.start < symbol.range.start
body_offset = data.index(b'Expect(1')
try:
    declaration_range(a, path, TextRange(body_offset, body_offset + 6), 'FuncDecl')
except ValueError:
    pass
else:
    raise AssertionError('body occurrence accepted as declaration name')
try:
    declaration_range(a, path, symbol.selectionRange, 'InterfaceDecl')
except ValueError:
    pass
else:
    raise AssertionError('wrong declaration kind accepted')
replacement = data[span.start:span.end].decode().replace('target()', 'renamed()')
report = workspace.applyChange(SourceChange([
    FileChange.EditFile(path, before, [TextEdit(span, replacement)])
]), a.revision)
assert report.isSuccess, report.error
assert report.failed is None
rows = result_page(range(5), offset=1, limit=2)
assert rows == dict(rows=[1, 2], total=5, returned=2, omitted=3, offset=1, next_offset=3)
assert result_page([], limit=1)['next_offset'] is None
for options in [dict(limit=0), dict(offset=-1), dict(limit=True)]:
    try:
        result_page([1], **options)
    except ValueError:
        pass
    else:
        raise AssertionError(options)
found = api_docs.find_symbol('FileChange.EditFile')
assert any(row['path'] == 'source_change/source_change.pyi' for row in found)
assert api_docs.find_symbol('DefinitelyAbsentType') == []
result = True
""")
            self.assertIsNone(response["error"], response)
            self.assertTrue(response["result"])
            after = (root / "src/example_test.cj").read_text()
            self.assertEqual(after, source.replace("target()", "renamed()"))
            fresh = self._api_docs_script(self.workflow_binary(), root, """
a = workspace.analysis()
path = 'src/example_test.cj'
assert len(exact_symbols(a, [path], 'renamed')) == 1
assert exact_symbols(a, [path], 'target') == []
assert workspace.loadDiagnostics == []
assert workspace.diagnostics(path) == []
span = declaration_range(a, path, exact_symbols(a, [path], 'renamed')[0][1].selectionRange, 'FuncDecl')
insertion = '@TestCase\\n    func inserted() { @Expect(3, 3) }\\n    '
report = workspace.applyChange(SourceChange([FileChange.EditFile(
    path, a.text(path), [TextEdit(TextRange(span.start, span.start), insertion)])
]), a.revision)
assert report.isSuccess, report.error
result = True
""")
            self.assertIsNone(fresh["error"], fresh)
            inserted = '@TestCase\n    func inserted() { @Expect(3, 3) }\n    '
            self.assertEqual((root / "src/example_test.cj").read_text(),
                             after.replace('@TestCase\n    func renamed', inserted + '@TestCase\n    func renamed'))

    def test_parse_candidate_references_and_extension_members(self):
        with tempfile.TemporaryDirectory(prefix="cjmcp-parse-references-") as directory:
            root = Path(directory)
            (root / "src").mkdir()
            (root / "cjpm.toml").write_text(
                '[package]\nname = "sample"\nversion = "0.1.0"\noutput-type = "static"\n')
            (root / "src/main.cj").write_text("""package sample
func parse(x: String): Int64 { 1 }
func parse(x: Array<Byte>): Int64 { 2 }
open class Value {}
class Object <: Value {}
class Context<T> {}
interface ParseTable<T> where T <: ParseTable<T> {
    static func parse(ctx: Context<T>, tv: ?Value): T {
        if (let Some(v) <- tv && let Some(obj) <- (v as Object)) {
            return parse(ctx, obj)
        }
        throw Exception("missing")
    }
    static func parse(ctx: Context<T>, obj: Object): T
}
extend String {
    public func adapterValue(): Int64 { 1 }
}
func use(x: String): Int64 { x.adapterValue() }
""")
            response = self._api_docs_script(self.workflow_binary(), root, """
a = workspace.analysis()
path = 'src/main.cj'
data = a.text(path).encode()
site = data.index(b'parse(ctx, obj)')
occurrence = a.semantic().at(a.fileId(path), site)
# Preserve the reproducer: this is conservative candidate evidence, not a call.
assert occurrence.resolution().status.kind == 'AmbiguousMeaning'
assert len(occurrence.definitions) == 4
free = [n for n in workspace.structure(path) if n.name == 'parse']
assert len(free) == 2
for symbol in free:
    assert site in [r.range.start for r in a.references(path, symbol.selectionRange.start)]
extension = next(n for n in workspace.structure(path) if n.name == 'String')
member = next(n for n in extension.children if n.name == 'adapterValue')
type_refs = a.references(path, extension.selectionRange.start)
member_refs = a.references(path, member.selectionRange.start)
assert all(data[r.range.start:r.range.end] == b'String' for r in type_refs)
assert all(data[r.range.start:r.range.end] == b'adapterValue' for r in member_refs)
assert len(member_refs) == 2
assert sum(r.isDeclaration for r in member_refs) == 1
result = {'status': occurrence.resolution().status.kind,
          'type_references': len(type_refs), 'member_references': len(member_refs)}
""")
            self.assertIsNone(response["error"], response)
            self.assertEqual(response["result"]["member_references"], 2)


    def test_library_dependency_adapter_boundary(self):
        with tempfile.TemporaryDirectory(prefix="cjmcp-library-boundary-") as directory:
            root = Path(directory)
            (root / "src").mkdir()
            (root / "deps/library/src").mkdir(parents=True)
            (root / "deps/corelib/src").mkdir(parents=True)
            (root / "cjpm.toml").write_text(
                '[package]\nname = "consumer"\nversion = "0.1.0"\noutput-type = "static"\n'
                '[dependencies]\nlibrary = { path = "deps/library" }\n')
            (root / "deps/library/cjpm.toml").write_text(
                '[package]\nname = "library"\nversion = "0.1.0"\noutput-type = "static"\n'
                '[dependencies]\ncorelib = { path = "../corelib" }\n')
            (root / "deps/corelib/cjpm.toml").write_text(
                '[package]\nname = "corelib"\nversion = "0.1.0"\noutput-type = "static"\n')
            (root / "deps/corelib/src/lib.cj").write_text(
                'package corelib\npublic func value(): Int64 { 1 }\n')
            (root / "deps/library/src/lib.cj").write_text(
                'package library\nimport corelib.value\npublic func parseToml(x: String): Int64 { value() }\n')
            (root / "src/adapter.cj").write_text(
                'package consumer\nimport library.parseToml\n'
                'func decode(x: String): Int64 { parseToml(x) }\n')
            (root / "src/main.cj").write_text(
                'package consumer\nfunc use(): Int64 { decode("x") }\n')
            recipe = (Path(__file__).resolve().parents[2] /
                      "modules/cjmcp/skills/cangjie-mcp/references/library.md").read_text()
            code = recipe.split("~~~python\n", 1)[1].split("~~~", 1)[0]
            response = self._api_docs_script(self.workflow_binary(), root, code)
            self.assertIsNone(response["error"], response)
            result = response["result"]
            self.assertEqual(result["load_diagnostics"], [])
            dependency = next(d for d in result["dependencies"]["rows"] if d["name"] == "library")
            self.assertTrue(dependency["resolved"])
            transitive = next(d for d in result["dependencies"]["rows"] if d["name"] == "corelib")
            self.assertTrue(transitive["resolved"])
            self.assertGreater(result["library"]["references"]["total"], 0)
            self.assertGreater(result["adapter"]["references"]["total"], 0)
            self.assertEqual(result["library"]["violations"]["total"], 0)
            self.assertEqual(result["library"]["uncertain"]["total"], 0)
            self.assertEqual(result["adapter"]["uncertain"]["total"], 0)
            # A direct use is a real boundary violation, even if diagnostics are empty.
            (root / "src/main.cj").write_text(
                'package consumer\nimport library.parseToml\n'
                'func use(): Int64 { decode("x") + parseToml("bypass") }\n')
            response = self._api_docs_script(self.workflow_binary(), root, code)
            self.assertIsNone(response["error"], response)
            violations = response["result"]["library"]["violations"]
            self.assertGreater(violations["total"], 0)
            self.assertTrue(all(r["path"].endswith("/src/main.cj") for r in violations["rows"]))

    @staticmethod
    def workflow_binary():
        from test_server import BINARY
        return BINARY
