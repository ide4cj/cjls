"""Drive embedded Python through the real MCP process, with stdin kept open."""

import hashlib
import json
import os
from pathlib import Path
import queue
import subprocess
import sys
import tempfile
import textwrap
import threading
import unittest

from output_checks import OutputChecks
from diagnostic_checks import DiagnosticChecks
from worktree_checks import WorktreeChecks
from semantic_checks import SemanticChecks

ROOT = Path(__file__).resolve().parents[2]
BINARY = os.environ.get("CJMCP_BIN", str(ROOT / "target/release/bin/cjmcp"))


def server_environment():
    env = {**os.environ, "cjHeapSize": "2GB"}
    # The driver and embedded interpreter can use different Python installations.
    if "CJMCP_PYTHONHOME" in env:
        env["PYTHONHOME"] = env["CJMCP_PYTHONHOME"]
    return env


@unittest.skipUnless(sys.platform.startswith("linux"), "embedded CPython experiment supports native Linux")
class McpStdioTest(WorktreeChecks, DiagnosticChecks, OutputChecks, SemanticChecks, unittest.TestCase):
    def test_supplied_api_docs(self):
        # An unrelated analyzed project and cwd must not override the server's reference.
        with tempfile.TemporaryDirectory(prefix="cjmcp-api-docs-") as directory:
            root = Path(directory)
            fake = root / "api_docs/cjmcp/python.pyi"
            fake.parent.mkdir(parents=True)
            fake.write_text("unrelated workspace documentation", encoding="utf-8")
            response = self._api_docs_script(BINARY, root, """
import hashlib
paths = api_docs.files()
assert paths == sorted(set(paths))
assert 'cjmcp/python.pyi' in paths
assert 'cjmcp/analysis.pyi' in paths
assert 'loupe.hir/def_map.pyi' in paths
assert 'class Workspace:' in api_docs.read('cjmcp/python.pyi')
assert "see 'loupe.hir/def_map.pyi'" in api_docs.read('cjmcp/analysis.pyi')
assert 'class DefId:' in api_docs.read('loupe.hir/def_map.pyi')
for path in ('/cjmcp/python.pyi', '../outside.pyi', 'cjmcp/../../outside.pyi', 'README.md'):
    for operation in (api_docs.read, api_docs.outline,
                      lambda path: api_docs.read_symbol(path, 'Workspace')):
        try:
            operation(path)
        except ValueError:
            pass
        else:
            raise AssertionError('invalid documentation path accepted: ' + path)
try:
    api_docs.read('missing.pyi')
except FileNotFoundError:
    pass
else:
    raise AssertionError('missing documentation file accepted')
result = {path: hashlib.sha256(api_docs.read(path).encode('utf-8')).hexdigest()
          for path in paths}
""")
        self.assertIsNone(response["error"], response)
        docs = ROOT / "modules/cjmcp/api_docs"
        expected = {
            path.relative_to(docs).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in docs.rglob("*.pyi")
        }
        self.assertTrue(expected)
        self.assertEqual(response["result"], expected)

    def test_api_doc_selection(self):
        with tempfile.TemporaryDirectory(prefix="cjmcp-api-selection-") as directory:
            response = self._api_docs_script(BINARY, Path(directory), '''
import ast
path = 'loupe.hir/body.pyi'
top = api_docs.outline(path)
assert any(item['symbol'] == 'Expr' and item['kind'] == 'class' for item in top)
members = api_docs.outline(path, 'Expr')
assert any(item['symbol'] == 'Expr.CallExpr' for item in members)
selected = api_docs.read_symbol(path, 'Expr.CallExpr')
assert 'class CallExpr(Expr):' in selected
assert 'class IndexExpr' not in selected
ast.parse(selected)
assert '@property' in api_docs.read_symbol(path, 'BodySourceMap.exprs')
try:
    api_docs.read_symbol(path, 'Expr', max_bytes=1)
except ValueError as error:
    assert 'outline' in str(error) and 'requires' in str(error)
else:
    raise AssertionError('oversized selection accepted')
assert 'class Expr:' in api_docs.read_symbol(path, 'Expr', max_bytes=100000)

# Cover syntax not present in every generated reference, without importing stubs.
fixture = """from typing import overload
class Café:
    'Unicode documentation.'
    value: str
    @overload
    def call(self, value: int) -> int: ...
    @overload
    def call(self, value: str) -> str: ...
    @property
    def name(self) -> str: ...
    @name.setter
    def name(self, value: str): ...
    class Nested:
        async def run(self): ...
alias = Café
"""
class FixtureDocs(type(api_docs)):
    def read(self, path):
        return fixture
docs = FixtureDocs()
assert [n['symbol'] for n in docs.outline('fixture.pyi')] == ['Café', 'alias']
assert 'Unicode documentation.' in docs.read_symbol('fixture.pyi', 'Café')
overloads = docs.read_symbol('fixture.pyi', 'Café.call')
assert overloads.count('@overload') == 2
assert overloads.count('def call') == 2
assert docs.read_symbol('fixture.pyi', 'Café.name').count('def name') == 2
assert 'async def run' in docs.read_symbol('fixture.pyi', 'Café.Nested.run')
lines = fixture.splitlines()
for item in docs.outline('fixture.pyi', 'Café'):
    selection = docs.read_symbol('fixture.pyi', item['symbol'])
    assert lines[item['line']-1].strip() in selection
    assert lines[item['end_line']-1].strip() in selection
    ast.parse(selection)
for symbol, error_type in [('Missing', KeyError), ('Café.missing', KeyError),
                           ('', ValueError), ('Café..call', ValueError), (1, TypeError)]:
    for operation in (docs.outline, docs.read_symbol):
        try:
            operation('fixture.pyi', symbol)
        except error_type:
            pass
        else:
            raise AssertionError('invalid symbol accepted')
try:
    docs.outline('fixture.pyi', 'Café.call')
except ValueError:
    pass
else:
    raise AssertionError('function used as outline container')
for budget, error_type in [(0, ValueError), (-1, ValueError), (True, TypeError), ('1', TypeError)]:
    try:
        docs.read_symbol('fixture.pyi', 'Café', max_bytes=budget)
    except error_type:
        pass
    else:
        raise AssertionError('invalid byte budget accepted')
size = len(docs.read_symbol('fixture.pyi', 'Café').encode('utf-8'))
assert docs.read_symbol('fixture.pyi', 'Café', max_bytes=size)
try:
    docs.read_symbol('fixture.pyi', 'Café', max_bytes=size-1)
except ValueError:
    pass
else:
    raise AssertionError('UTF-8 byte budget was not enforced')
result = True
''')
        self.assertIsNone(response["error"], response)
        self.assertTrue(response["result"])

    def test_missing_api_docs_reports_error_without_workspace_fallback(self):
        with tempfile.TemporaryDirectory(prefix="cjmcp-no-api-docs-") as directory:
            root = Path(directory)
            # Relocate the executable without its reference, while the project has a fake copy.
            binary = root / "cjmcp"
            try:
                os.link(Path(BINARY).resolve(), binary)
            except OSError:
                import shutil
                shutil.copy2(BINARY, binary)
            fake = root / "project/api_docs/cjmcp/python.pyi"
            fake.parent.mkdir(parents=True)
            fake.write_text("unrelated workspace documentation", encoding="utf-8")
            response = self._api_docs_script(binary, root / "project", """
assert isinstance(workspace.files(), list)
for operation in (api_docs.files, lambda: api_docs.read('cjmcp/python.pyi'),
                  lambda: api_docs.outline('cjmcp/python.pyi'),
                  lambda: api_docs.read_symbol('cjmcp/python.pyi', 'Workspace')):
    try:
        operation()
    except FileNotFoundError as error:
        assert 'beside the executable' in str(error)
    else:
        raise AssertionError('missing server documentation must be reported')
result = True
""")
        self.assertIsNone(response["error"], response)
        self.assertTrue(response["result"])

    def _api_docs_script(self, binary, root, code):
        messages = [
            {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
                "protocolVersion": "2025-11-25", "capabilities": {},
                "clientInfo": {"name": "api-docs-test", "version": "1"},
            }},
            {"jsonrpc": "2.0", "method": "notifications/initialized"},
            {"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {
                "name": "runPython", "arguments": {"code": code},
            }},
        ]
        process = subprocess.run(
            [str(Path(binary).resolve()), "--dir", str(root)], cwd=root,
            input="".join(json.dumps(message) + "\n" for message in messages),
            capture_output=True, text=True, timeout=60, env=server_environment(),
        )
        self.assertEqual(process.returncode, 0, process.stderr)
        replies = [json.loads(line) for line in process.stdout.splitlines()]
        initialization = next(reply["result"] for reply in replies if reply.get("id") == 1)
        self.assertIn("apiDocs", initialization["serverInfo"]["_meta"]["features"])
        reply = next(reply for reply in replies if reply.get("id") == 2)
        self.assertNotIn("error", reply)
        self.assertFalse(reply["result"]["isError"], reply)
        return reply["result"]["structuredContent"]

    def test_repeated_native_proxy_allocation(self):
        # Reentering through enum constructors and payload getters exposed invalid GC roots.
        # This needs the real process: an interpreter crash cannot become a tool error.
        expected_version = os.environ.get("CJMCP_PYTHON_VERSION")
        version_check = (
            "import sys\n"
            f"assert {expected_version!r} is None or '.'.join(map(str, sys.version_info[:2])) == {expected_version!r}, sys.version\n"
        )
        code = version_check + """
assert {'start', 'end', 'len'} <= set(dir(TextRange))
assert Expr.CallExpr.__match_args__ == ('field0', 'field1')
span = TextRange(1, 4)
assert span.len == 3
try:
    span.len = 10
except AttributeError:
    pass
else:
    raise AssertionError('native immutable fields must remain read-only')
diagnostic = InferenceDiagnostic.CustomAnnotationPlace(ExprId(3))
assert diagnostic.field0 == ExprId(3)
assert diagnostic == InferenceDiagnostic.CustomAnnotationPlace(ExprId(3))
assert diagnostic != InferenceDiagnostic.CustomAnnotationPlace(ExprId(4))
for i in range(100000):
    value = Expr.CallExpr(ExprId(i), [])
    assert value.kind == 'CallExpr'
    assert value.field0.index == i
    assert value.field1 == []
result = i + 1
"""
        messages = [
            {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
                "protocolVersion": "2025-11-25", "capabilities": {},
                "clientInfo": {"name": "proxy-allocation-test", "version": "1"},
            }},
            {"jsonrpc": "2.0", "method": "notifications/initialized"},
            {"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {
                "name": "runPython", "arguments": {"code": code},
            }},
        ]
        with tempfile.TemporaryDirectory(prefix="cjmcp-proxies-") as directory:
            process = subprocess.run(
                [BINARY, "--dir", directory],
                input="".join(json.dumps(message) + "\n" for message in messages),
                capture_output=True, text=True, timeout=60,
                env=server_environment(),
            )
        self.assertEqual(process.returncode, 0, process.stderr)
        replies = [json.loads(line) for line in process.stdout.splitlines()]
        reply = next(reply for reply in replies if reply.get("id") == 2)
        self.assertNotIn("error", reply)
        response = reply["result"]
        self.assertFalse(response["isError"], response)
        self.assertEqual(response["structuredContent"]["result"], 100000)

    def test_python_native_objects_errors_output_and_reload(self):
        self._check_workspace(macros_only=False)

    def test_macros_finish_before_revision_and_reload(self):
        self._check_workspace(macros_only=True)

    def test_worktree_sessions(self):
        self._check_workspace(macros_only=False, worktrees_only=True)

    def _check_workspace(self, *, macros_only, worktrees_only=False):
        # arrange
        with tempfile.TemporaryDirectory(prefix="cjmcp-") as directory:
            root = Path(directory)
            (root / "src").mkdir()
            (root / "cjpm.toml").write_text(
                '[package]\nname = "sample"\nversion = "0.1.0"\noutput-type = "executable"\n',
                encoding="utf-8", newline="\n",
            )
            (root / "src/helper.cj").write_text(
                "package sample\npublic func shared(): Int64 { 42 }\n"
                "public func shared(value: Int64): Int64 { value }\n"
                "public func identity<T>(value: T): T { value }\n"
                "public func identity(first: Int64, second: Int64): Int64 { first + second }\n", encoding="utf-8", newline="\n",
            )
            source = "package sample\n// привет\npublic func answer(): Int64 { let local = identity(shared()); local }\nmain() { answer() }\n"
            (root / "src/main.cj").write_text(source, encoding="utf-8", newline="\n")
            (root / "src/nested.cj").write_text(
                "package sample\n"
                "class First { var value: Int64 = 1; func read(): Int64 { value } }\n"
                "class Second { var value: Int64 = 2; func read(): Int64 { value } }\n"
                "enum Choice { Left | Right(Int64) }\n",
                encoding="utf-8", newline="\n",
            )
            process = subprocess.Popen(
                [BINARY, "--dir", str(root)], stdin=subprocess.PIPE,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                env=server_environment(),
            )
            replies = queue.Queue()

            def read_replies():
                for line in process.stdout:
                    replies.put(line)
                replies.put(None)

            reader = threading.Thread(target=read_replies, daemon=True)
            reader.start()
            next_id = 0

            def rpc(method, params=None):
                nonlocal next_id
                next_id += 1
                message = {"jsonrpc": "2.0", "id": next_id, "method": method}
                if params is not None:
                    message["params"] = params
                wire = json.dumps(message, ensure_ascii=False).encode() + b"\r\n"
                process.stdin.write(wire[:8])
                process.stdin.flush()
                process.stdin.write(wire[8:])
                process.stdin.flush()
                raw = replies.get(timeout=60)
                if raw is None:
                    process.wait(timeout=10)
                    self.fail(f"server closed stdout ({process.returncode}): {process.stderr.read().decode(errors='replace')}")
                reply = json.loads(raw)
                self.assertEqual(reply["id"], next_id)
                self.assertNotIn("error", reply)
                return reply["result"]

            def run(code, *, error=False, max_output_bytes=None, root=None):
                arguments = {"code": textwrap.dedent(code)}
                if root is not None:
                    arguments["root"] = str(root)
                if max_output_bytes is not None:
                    arguments["maxOutputBytes"] = max_output_bytes
                result = rpc("tools/call", {
                    "name": "runPython", "arguments": arguments,
                })
                self.assertEqual(result["isError"], error, result)
                self.assertEqual(json.loads(result["content"][0]["text"]), result["structuredContent"])
                data = result["structuredContent"]
                self.assertIsInstance(data["revision"], int, data)
                self.assertGreater(data["revision"], 0)
                return data

            try:
                # act - one Python call traverses native analysis objects from several queries
                initialization = rpc("initialize", {
                    "protocolVersion": "2025-11-25", "capabilities": {},
                    "clientInfo": {"name": "test", "version": "1"},
                })
                process.stdin.write(b'{"jsonrpc":"2.0","method":"notifications/initialized"}\n')
                process.stdin.flush()
                tools = rpc("tools/list")["tools"]
                info = initialization['serverInfo']
                self.assertEqual(info['name'], 'cjmcp')
                self.assertEqual(info['_meta']['apiVersion'], 1)
                self.assertIn('worktreeSessions', info['_meta']['features'])
                self.assertIn('semanticViews', info['_meta']['features'])
                if expected_commit := os.environ.get('CJMCP_BUILD_COMMIT'):
                    self.assertEqual(info['_meta']['commit'], expected_commit)
                if info['_meta']['commit'] is not None:
                    self.assertRegex(info['_meta']['commit'], r'^[0-9a-f]{40}$')
                    self.assertIsInstance(info['_meta']['dirty'], bool)
                identity = run('result = server_info')['result']
                self.assertEqual(identity, info)
                run("server_info['_meta']['features'].clear(); server_info['name'] = 'changed'")
                self.assertEqual(run('result = server_info')['result'], info)
                if worktrees_only:
                    self._check_worktree_sessions(root, rpc, run)
                    return
                if macros_only:
                    self._check_macros(root, run)
                    return
                # Keep 3.10 syntax out of the script parsed by an embedded Python 3.9.
                pattern_match = """match analysis.typeKind(inferred.locals[local]):
    case TyKind.PrimTy(name):
        assert name == 'Int64'
    case _:
        raise AssertionError('inferred enum lost its variant')
"""
                native = run(f"""
                    assert {{'files', 'structure', 'analysis'}} <= set(dir(type(workspace)))
                    analysis = workspace.analysis()
                    assert {{'symbols', 'references', 'infer', 'text'}} <= set(dir(type(analysis)))
                    nodes = workspace.structure('src/main.cj')
                    assert all(isinstance(node, StructureNode) for node in nodes)
                    assert all(isinstance(node.range, TextRange) for node in nodes)
                    assert all(node.range.len == node.range.end - node.range.start for node in nodes)
                    span = TextRange(1, 4)
                    assert span.len == 3 and span.contains(2) and not span.contains(4)
                    assert span.shift(2) == TextRange(3, 6)
                    assert all(isinstance(node.kind, StructureKind) for node in nodes)
                    assert any(node.kind.toString() == 'Function' for node in nodes)
                    hover = workspace.hover('src/main.cj', {source.encode().rindex(b'answer')})
                    assert isinstance(hover, HoverResult)
                    assert isinstance(hover.items[0], HoverItem)
                    location = workspace.definition('src/main.cj', {source.encode().index(b'shared')})[0]
                    related = analysis.related('src/main.cj', {source.encode().rindex(b'answer')})
                    assert len(related) == 2
                    assert all(isinstance(item, RelatedHighlight) for item in related)
                    assert related == analysis.related('src/main.cj', {source.encode().rindex(b'answer')})
                    assert related[0].access is None
                    assert related[1].access == ReferenceAccess.ReadAccess()
                    assert related[1].access != ReferenceAccess.WriteAccess()
                    result = {{
                        'files': workspace.files(),
                        'symbols': [node.name for node in nodes],
                        'hover': hover.items[0].code,
                        'target': location.path,
                        'loadDiagnostics': workspace.loadDiagnostics,
                        'macros': workspace.macros,
                        'diagnostics': [item.message for item in workspace.diagnostics('src/main.cj')],
                    }}
                    print('прямые объекты loupe')
                """)

                # assert
                self.assertEqual(initialization["protocolVersion"], "2025-11-25")
                self.assertEqual([tool["name"] for tool in tools], ["runPython"])
                data = native["result"]
                self.assertIn(str(root / "src/main.cj"), data["files"])
                self.assertIn("answer", data["symbols"])
                self.assertIn("answer", data["hover"])
                self.assertEqual(data["target"], str(root / "src/helper.cj"))
                self.assertEqual(data["diagnostics"], [])
                self.assertEqual(data["macros"], {"state": "settled", "diagnostics": []})
                self.assertIn("прямые объекты loupe", native["stdout"])

                unchanged = run("result = workspace.revision")
                self.assertEqual(unchanged["revision"], native["revision"])
                self.assertEqual(unchanged["result"], native["revision"])

                self._check_semantic_exports(root, run)
                self._check_structured_diagnostics(run)
                self._check_output_budgets(root, run)
                self._check_source_excerpts(run)
                self._check_large_source_workflow(run)
                self._check_source_editing(run)
                self._check_source_changes(run)

                # Native exceptions must return through Python's error protocol before another query.
                recovered = run("""
                    analysis = workspace.analysis()
                    for _ in range(3):
                        try:
                            analysis.declarations('src/missing.cj')
                        except RuntimeError as error:
                            assert 'file is not loaded' in str(error), str(error)
                        else:
                            raise AssertionError('missing file was accepted')
                    assert analysis.declarations('src/main.cj')
                    result = True
                """)
                self.assertTrue(recovered["result"])

                nested = run("""
                    a = workspace.analysis()
                    declarations = a.declarations('src/nested.cj')
                    items = [a.item(d) for d in declarations]
                    assert all(isinstance(item, Item) for item in items), items
                    by_id = dict(zip(declarations, items))
                    members = [d for d in declarations if a.parent(d) is not None]
                    assert len(members) == 6, members
                    for d in members:
                        item = by_id[d]
                        assert item.id == a.definitionItem(d)
                        assert item in by_id[a.parent(d)].members
                    result = sorted(name for d in members for name in by_id[d].names)
                """)
                self.assertEqual(nested["result"], ["Left", "Right", "read", "read", "value", "value"])

                # act - inspect generic inference and its HIR, then navigate the selected callee
                inference = run(f"""
                    analysis = workspace.analysis()
                    defs = analysis.declarations('src/main.cj')
                    answer = next(d for d in defs if 'answer' in analysis.item(d).names)
                    assert isinstance(answer, DefId)
                    owner = GenericOwner.Declaration(answer)
                    local_owner = GenericOwner.LocalFunction(answer, 0)
                    assert owner == GenericOwner.Declaration(answer) and owner != local_owner
                    assert len({{owner, GenericOwner.Declaration(answer), local_owner}}) == 2
                    parameter = analysis.internType(TyKind.ParamTy(owner, 0))
                    assert analysis.typeKind(parameter).field0 == owner
                    assert analysis.typeKind(parameter).field0.field0 == answer
                    assert isinstance(analysis.definitionItem(answer), ItemId)
                    assert isinstance(analysis.definitionFile(answer), ItemFile)
                    body = analysis.body(answer)
                    inferred = analysis.infer(answer)
                    assert isinstance(body, Body) and isinstance(inferred, InferenceResult)
                    assert all(isinstance(expr, Expr) for expr in body.exprs)
                    assert all(isinstance(local, Local) for local in body.locals)
                    assert all(isinstance(ty, Ty) for ty in inferred.locals)
                    assert len(body.exprs) == len(inferred.exprs)
                    local = next(i for i, value in enumerate(body.locals) if value.name == 'local')
                    assert analysis.typeText(inferred.locals[local]) == 'Int64'
                    assert inferred[LocalId(local)] == inferred.locals[local]
                    assert len(set([inferred.locals[local], analysis.internType(TyKind.PrimTy('Int64'))])) == 1
                    assert ExprId(1) == ExprId(1) and hash(ExprId(1)) == hash(ExprId(1))
                    assert ExprId(1) != ExprId(2)
                    assert len({{ExprId(1), ExprId(1), ExprId(2)}}) == 2
                    assert str(ExprId(1)) == 'ExprId(index: 1)'
                    assert ItemKind.Func() != ItemKind.Main()
                    assert len({{ItemKind.Func(), ItemKind.Func(), ItemKind.Main()}}) == 2
                    assert Local('a', LocalKind.VarLocal(), lone=False) == Local('a', LocalKind.VarLocal(), lone=False)
                    assert Local('a', LocalKind.VarLocal(), lone=False) != Local('b', LocalKind.VarLocal(), lone=False)
                    assert Expr.LitExpr('42') == Expr.LitExpr('42')
                    assert Expr.LitExpr('42') != Expr.LitExpr('43')
                    assert Expr.LitExpr('42') != Expr.MissingExpr()
                    assert Expr.StrExpr([ExprId(1)]) == Expr.StrExpr([ExprId(1)])
                    assert Expr.StrExpr([ExprId(1)]) != Expr.StrExpr([ExprId(2)])
                    assert analysis.typeKind(inferred.locals[local]) == TyKind.PrimTy('Int64')
                    assert isinstance(analysis.typeKind(inferred.locals[local]), TyKind.PrimTy)
                    assert analysis.typeKind(inferred.locals[local]).field0 == 'Int64'
                    import sys
                    if sys.version_info >= (3, 10):
                        exec({pattern_match!r})
                    assert analysis.typeText(analysis.internType(TyKind.PrimTy('Bool'))) == 'Bool'
                    assert not analysis.isTypeUnknown(inferred.locals[local])
                    assert inferred.diagnostics == []
                    assert isinstance(analysis.signature(answer), Signature)
                    assert isinstance(analysis.signatureTypes(answer), SignatureTypes)
                    assert analysis.typeText(analysis.declaredType(answer)) == 'Int64'
                    lowered = analysis.loweredBody(answer)
                    assert isinstance(lowered, LoweredBody)
                    assert isinstance(lowered.sourceMap, BodySourceMap)
                    written = [origin.written for origin in lowered.sourceMap.exprs if origin.written is not None]
                    assert written and all(isinstance(source, BodySource) for source in written)
                    assert all(isinstance(source.range, TextRange) for source in written)
                    assert all(source.expansion is None for source in written)
                    assert isinstance(analysis.scopes(answer), ExprScopes)
                    assert analysis.path(analysis.fileId('src/main.cj')).endswith('/src/main.cj')
                    assert analysis.text('src/main.cj').encode()[written[0].range.start:written[0].range.end]
                    assert len(analysis.expressionRanges(answer)) == len(body.exprs)
                    assert len(analysis.localRanges(answer)) == len(body.locals)
                    assert all(span is None or isinstance(span, TextRange)
                               for span in analysis.expressionRanges(answer))
                    callees = [inferred.calleeOf(ExprId(i)) for i in range(len(body.exprs))]
                    names = [name for d in callees if d is not None for name in analysis.item(d).names]
                    assert 'shared' in names and 'identity' in names, names
                    direct = analysis.directCalls(answer)
                    assert isinstance(direct, DirectCalls)
                    assert len(direct.edges) == 2
                    assert all(isinstance(edge, DirectCall) for edge in direct.edges)
                    assert all(isinstance(gap, CallGap) for gap in direct.gaps)
                    declared = [analysis.callDeclaration(edge.target) for edge in direct.edges]
                    assert all(isinstance(item, CallDeclaration) for item in declared)
                    assert {{item.name for item in declared}} == {{'identity', 'shared'}}
                    assert all(item.packageName == 'sample' for item in declared)
                    assert all(isinstance(target, CalleeTarget) for target in inferred.callees)
                    assert all(isinstance(target, NameTarget) for target in inferred.names)
                    assert all(isinstance(target.resolution, BodyResolution) for target in inferred.names)
                    assert isinstance(Expr.LitExpr('42'), Expr)
                    assert any(isinstance(expr, Expr.CallExpr) for expr in body.exprs)
                    assert isinstance(InferenceDiagnostic.TypeMismatch(
                        ExprId(0), inferred.locals[local], inferred.locals[local]), InferenceDiagnostic)
                    assert CfgExpr.CfgFlag('test', False).evaluate(Cfg([('test', 'true')]))
                    scope = analysis.typeScope(answer)
                    assert isinstance(scope, TypeScope)
                    assert analysis.path(analysis.sourceFileId(scope.file)).endswith('/src/main.cj')
                    assert HighlightModifiers.NONE.isEmpty()
                    refs = analysis.references('src/main.cj', {source.encode().rindex(b'answer')})
                    assert refs and all(isinstance(ref, Reference) for ref in refs)
                    assert all(analysis.path(ref.fileId).endswith('.cj') for ref in refs)
                    completions = analysis.completions('src/main.cj', {source.encode().index(b'identity')})
                    assert isinstance(completions, CompletionResult)
                    completion = next(item for item in completions.items if item.label == 'shared')
                    assert isinstance(completion.source, CompletionSource)
                    assert analysis.completionDetails('src/main.cj', {source.encode().index(b'identity')}, completion)
                    assert all(isinstance(item, HighlightedRange) for item in analysis.highlights('src/main.cj'))
                    assert all(isinstance(item, Fold) for item in analysis.folding('src/main.cj'))
                    symbols = analysis.symbols('answer', 10)
                    assert symbols and all(isinstance(item, FoundSymbol) for item in symbols)
                    assert analysis.selection('src/main.cj', {source.encode().rindex(b'answer')})
                    # A reload requested inside Python is deferred; this script keeps its revision.
                    workspace.reload()
                    assert analysis.typeText(analysis.infer(answer).locals[local]) == 'Int64'
                    result = names
                """)
                self.assertIn("identity", inference["result"])

                self._check_query_exports(root, run)
                self._check_call_hierarchy(root, run)

                # act - fd output, exceptions and unserializable objects stay off the MCP wire
                captured = run("""
                    import ctypes, os, sys
                    print('python output')
                    print('python error output', file=sys.stderr)
                    print('original stream', file=sys.__stdout__)
                    os.write(1, b'fd output\\n')
                    ctypes.CDLL(None).printf(b'native output\\n')
                    result = 42
                """)
                failed = run("print('before failure')\nraise ValueError('script failure')", error=True)
                bad_result = run("result = workspace.structure('src/main.cj')", error=True)
                bad_offset = run(
                    f"workspace.hover('src/main.cj', {source.encode().index('п'.encode()) + 1})", error=True,
                )
                self.assertIn('offset must be a UTF-8 byte boundary', bad_offset["error"])
                recovered = run("result = 6 * 7")

                # assert
                self.assertIn("python output", captured["stdout"])
                self.assertIn("fd output", captured["stdout"])
                self.assertIn("native output", captured["stdout"])
                self.assertIn("original stream", captured["stdout"])
                self.assertIn("python error output", captured["stderr"])
                self.assertIn("script failure", failed["error"])
                self.assertIn("before failure", failed["stdout"])
                self.assertIn("serializable", bad_result["error"])
                self.assertEqual(recovered["result"], 42)

                # Coordinate an edit from outside Python while a script is running.
                # The script must retain its text, IDs and revision until its response is serialized.
                ready = root / "script-ready"
                released = root / "edit-finished"
                editing_errors = []

                def edit_during_script():
                    try:
                        import time
                        deadline = time.monotonic() + 30
                        while not ready.exists():
                            if time.monotonic() > deadline:
                                raise TimeoutError("script did not reach the barrier")
                            time.sleep(0.01)
                        (root / "src/helper.cj").write_text(
                            "package sample\npublic func editedDuringScript(): Int64 { 43 }\n",
                            encoding="utf-8", newline="\n",
                        )
                    except BaseException as error:
                        editing_errors.append(error)
                    finally:
                        released.touch()

                editor = threading.Thread(target=edit_during_script)
                editor.start()
                try:
                    frozen = run("""
                        import time
                        from pathlib import Path
                        a = workspace.analysis()
                        before = a.text('src/helper.cj')
                        revision = workspace.revision
                        Path(workspace.root, 'script-ready').touch()
                        deadline = time.monotonic() + 30
                        while not Path(workspace.root, 'edit-finished').exists():
                            assert time.monotonic() < deadline, 'editor did not release script'
                            time.sleep(0.01)
                        assert a.text('src/helper.cj') == before
                        assert workspace.analysis().text('src/helper.cj') == before
                        assert workspace.revision == a.revision == revision
                        result = revision
                    """)
                finally:
                    editor.join(timeout=35)
                self.assertEqual(editing_errors, [])
                self.assertEqual(frozen['result'], frozen['revision'])
                applied = run("result = workspace.analysis().text('src/helper.cj')")
                self.assertIn('editedDuringScript', applied['result'])
                self.assertGreater(applied['revision'], frozen['revision'])

                # Source freshness compares contents even when an editor preserves size and mtime.
                helper = root / 'src/helper.cj'
                stamp = helper.stat()
                helper.write_text(helper.read_text().replace('43', '44'), encoding='utf-8')
                os.utime(helper, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
                same_stamp = run("result = workspace.analysis().text('src/helper.cj')")
                self.assertIn('44', same_stamp['result'])
                self.assertGreater(same_stamp['revision'], applied['revision'])

                # act - edits/additions/deletions are synchronized automatically before each script
                (root / "src/main.cj").write_text(
                    "package sample\n// комментарий\nmain() { /* привет */ let value: Int64 = true }\n", encoding="utf-8", newline="\n",
                )
                (root / "src/new.cj").write_text(
                    "package sample\npublic func added() {}\n", encoding="utf-8", newline="\n",
                )
                stale = run("result = [node.name for node in workspace.structure('src/main.cj')]")
                changed = run("""
                    diagnostics = workspace.diagnostics('src/main.cj')
                    assert all(isinstance(item, WorkspaceDiagnostic) for item in diagnostics)
                    assert all(isinstance(item.severity, Severity) for item in diagnostics)
                    analysis = workspace.analysis()
                    main = next(d for d in analysis.declarations('src/main.cj') if analysis.item(d).kind == ItemKind.Main())
                    mismatch = next(d for d in analysis.infer(main).diagnostics
                                    if isinstance(d, InferenceDiagnostic.TypeMismatch))
                    assert isinstance(mismatch.field0, ExprId)
                    assert analysis.typeText(mismatch.field1) == 'Int64'
                    assert analysis.typeText(mismatch.field2) == 'Bool'
                    assert isinstance(Severity.Error(), Severity)
                    result = dict(
                        diagnostics=diagnostics,
                        added=[node.name for node in workspace.structure('src/new.cj')])
                """)
                (root / "src/new.cj").unlink()
                after_delete = run("result = workspace.files()")

                # assert
                self.assertNotIn("answer", stale["result"])
                self.assertGreater(stale["revision"], recovered["revision"])
                self.assertTrue(any("mismatched types" in d["message"] for d in changed["result"]["diagnostics"]))
                diagnostic = next(d for d in changed["result"]["diagnostics"] if "mismatched types" in d["message"])
                source = (root / "src/main.cj").read_bytes()
                offset = source.index(b"true")
                self.assertEqual(diagnostic["source"], "analysis")
                self.assertEqual(diagnostic["severity"], "error")
                self.assertEqual(diagnostic["path"], str(root / "src/main.cj"))
                self.assertEqual(diagnostic["range"], {"start": offset, "end": offset + 4})
                self.assertEqual(diagnostic["line"], 3)
                self.assertEqual(diagnostic["column"], offset - source.rindex(b"\n", 0, offset))
                self.assertFalse(diagnostic["unnecessary"])
                self.assertIn("added", changed["result"]["added"])
                self.assertNotIn(str(root / "src/new.cj"), after_delete["result"])

                # Preparation failure must not execute Python against the last successful revision.
                moved = root.with_name(root.name + '-unavailable')
                root.rename(moved)
                try:
                    failure = rpc('tools/call', {
                        'name': 'runPython', 'arguments': {'code': "raise AssertionError('must not execute')"},
                    })
                    self.assertTrue(failure['isError'], failure)
                    self.assertIsNone(failure['structuredContent']['revision'])
                    self.assertIn('workspace directory does not exist', failure['structuredContent']['error'])
                finally:
                    moved.rename(root)
                resumed = run('result = workspace.revision')
                self.assertEqual(resumed['result'], resumed['revision'])
                self.assertNotEqual(resumed['sessionId'], after_delete['sessionId'])

            finally:
                process.stdin.close()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
                stderr = process.stderr.read().decode(errors="replace")
                process.stdout.close()
                process.stderr.close()
                reader.join(timeout=5)
                # Report native/Python startup failures even when an earlier RPC saw EOF.
                self.assertEqual(process.returncode, 0, stderr)

    def _check_query_exports(self, root, run):
        # Exercise the Python converters as well as the queries, including byte ranges after Unicode.
        (root / "src/types.cj").write_text(textwrap.dedent("""\
            package sample
            // типы
            open class Base { public func inherited(): Int64 { 1 } }
            class Box<T> <: Base {
                public func pick(value: T): T { value }
                public func pick(value: T, other: T): T { other }
            }
            extend<T> Box<T> { public func extra(): Int64 { 2 } }
        """), encoding="utf-8", newline="\n")
        (root / "src/format.cj").write_text(
            'package sample\n// привет\nfunc layout() {\nlet n = if (true) { 1 } else { 2 }\n}\n',
            encoding="utf-8", newline="\n",
        )
        (root / "src/broken.cj").write_text("package sample\nfunc broken(value:) {}\n", encoding="utf-8")
        (root / "src/canonical.cj").write_text("package sample\n", encoding="utf-8")
        response = run("""
            a = workspace.analysis()
            defs = a.declarations('src/types.cj')
            roots = [item for d in defs if (item := a.item(d)) is not None]
            box = next(d for d in defs if (item := a.item(d)) is not None and 'Box' in item.names)
            # Read nested item names through their owning Item, independent of item(def) traversal.
            by_id = {item.id: item for root in roots for item in [root, *root.members]}
            members = a.allMembers(box)
            assert members and all(isinstance(m, MemberTarget) for m in members)
            names = [name for member in members for name in by_id[a.definitionItem(member.field0)].names]
            assert names.count('pick') == 2, names
            assert 'inherited' in names and 'extra' in names, names
            assert a.allMembers(next(d for d in a.declarations('src/main.cj')
                                     if 'answer' in a.item(d).names)) == []
            pick = next(d for d in defs if 'pick' in by_id[a.definitionItem(d)].names)
            assert len(a.members(pick, 'pick')) == 2
            assert a.allMembers(pick) == members
            lowered = a.signatureWithSourceMap(pick)
            assert isinstance(lowered, LoweredSignature)
            assert isinstance(lowered.sourceMap, SignatureSourceMap)
            sig = lowered.signature
            ranges = lowered.sourceMap.ranges
            assert len(ranges) == len(sig.types)
            data = a.text('src/types.cj').encode('utf-8')
            for index, span in enumerate(ranges):
                assert isinstance(span, TextRange)
                assert data[span.start:span.end].decode('utf-8') == sig.text(TypeRefId(index))
                assert lowered.sourceMap.typeAtRange(span) == TypeRefId(index)
            assert lowered.sourceMap.typeAtRange(TextRange(0, 0)) is None
            main = next(d for d in a.declarations('src/main.cj') if a.item(d).kind == ItemKind.Main())
            assert a.signatureWithSourceMap(main).sourceMap.ranges == []
            missing = a.declarations('src/broken.cj')[0]
            assert None in a.signatureWithSourceMap(missing).sourceMap.ranges
            symbols = a.fileSymbols('src/types.cj')
            assert all(isinstance(s, FileSymbol) for s in symbols)
            assert [s.name for s in symbols].count('pick') == 2
            assert all(s.containerName == 'Box' for s in symbols if s.name == 'pick')
            for query, name in [(a.builtinTypeDoc, 'Int64'),
                                (a.builtinAnnotationDoc, 'When'),
                                (a.builtinMacroDoc, 'sourceLine')]:
                doc = query(name)
                assert isinstance(doc, BuiltinDoc) and doc.name == name and doc.code and doc.summary
                assert query('missingBuiltin') is None
            assert a.newFilePackageLine('src/new.cj') == 'package sample'
            assert a.newFilePackageLine('src/child/new.cj') == 'package sample.child'
            assert a.newFilePackageLine('outside/new.cj') is None
            original = a.text('src/format.cj')
            edits = a.formatting('src/format.cj')
            assert edits and all(isinstance(edit, TextEdit) for edit in edits)
            assert edits[0] == TextEdit(edits[0].range, edits[0].text)
            defaults = FormatOptions()
            assert (defaults.lineWidth, defaults.indentWidth) == (100, 4)
            assert isinstance(defaults.simpleIf, SimpleIf.Multiline)
            assert FormatOptions(indentWidth=2).indentWidth == 2
            assert BodyParam(None).ty is None
            assert Body().exprs == []
            for invalid in [lambda: FormatOptions(unknown=1),
                            lambda: FormatOptions(indentWidth='two'),
                            lambda: FormatOptions(100), lambda: Body(unknown=1)]:
                try:
                    invalid()
                except TypeError:
                    pass
                else:
                    raise AssertionError('invalid native arguments were accepted')
            options = FormatOptions(lineWidth=100, indentWidth=2, simpleIf=SimpleIf.Compact())
            assert options.lineWidth == 100 and options.indentWidth == 2
            assert isinstance(options.simpleIf, SimpleIf.Compact)
            def apply(edits):
                data = original.encode('utf-8')
                for edit in reversed(edits):
                    data = data[:edit.range.start] + edit.text.encode('utf-8') + data[edit.range.end:]
                return data.decode('utf-8')
            formatted = apply(a.formatting('src/format.cj', options=options))
            assert '\\n  let n = if (true) { 1 } else { 2 }\\n' in formatted, formatted
            start = original.encode('utf-8').index(b'let n')
            ranged = a.rangeFormatting('src/format.cj', TextRange(start, start + 3), options=options)
            assert ranged and '\\n  let n' in apply(ranged)
            assert a.text('src/format.cj') == original
            assert a.formatting('src/broken.cj') is None
            assert a.formatting('src/canonical.cj') == []
            assert a.rangeFormatting('src/broken.cj', TextRange(0, 0)) is None
            for action in [lambda: FormatOptions(lineWidth=100, indentWidth=0, simpleIf=SimpleIf.Multiline()),
                           lambda: a.rangeFormatting('src/format.cj', TextRange(0, 10000)),
                           lambda: a.rangeFormatting('src/format.cj', TextRange(0, original.encode().index('п'.encode()) + 1))]:
                try:
                    action()
                except RuntimeError:
                    pass
                else:
                    raise AssertionError('invalid formatting input was accepted')
            result = True
        """)
        self.assertTrue(response["result"])

    def _check_call_hierarchy(self, root, run):
        (root / "src/caller.cj").write_text(
            "package sample\n// вызовы\nfunc caller() { leaf(); leaf() }\n",
            encoding="utf-8", newline="\n",
        )
        (root / "src/leaf.cj").write_text(
            "package sample\npublic func leaf() {}\n", encoding="utf-8", newline="\n",
        )
        response = run("""
            a = workspace.analysis()
            caller_text = a.text('src/caller.cj').encode('utf-8')
            leaf_text = a.text('src/leaf.cj').encode('utf-8')
            caller = a.prepareCallHierarchy('src/caller.cj', caller_text.index(b'caller'))[0]
            leaf = a.prepareCallHierarchy('src/leaf.cj', leaf_text.index(b'leaf'))[0]
            assert isinstance(caller, CallHierarchyEntry) and caller.name == 'caller'
            assert caller.kind == StructureKind.Function()
            assert isinstance(caller.target, NavigationTarget)
            assert caller.definition is None and leaf.definition is None
            assert caller == CallHierarchyEntry(caller.name, caller.kind, caller.target)
            assert caller == CallHierarchyEntry(caller.name, caller.kind, caller.target, definition=None)
            identity = a.declarations('src/caller.cj')[0]
            identified = CallHierarchyEntry(caller.name, caller.kind, caller.target, definition=identity)
            assert identified.definition == identity and identified != caller
            assert identified == CallHierarchyEntry(caller.name, caller.kind, caller.target, definition=identity)
            assert caller != leaf
            assert a.prepareCallHierarchy('src/caller.cj', caller_text.index(b'leaf')) == [leaf]
            outgoing = a.outgoingCalls(caller)
            incoming = a.incomingCalls(leaf)
            assert len(outgoing) == len(incoming) == 1
            assert isinstance(outgoing[0], HierarchyCalls)
            assert outgoing[0].item == leaf and incoming[0].item == caller
            assert outgoing[0].ranges == incoming[0].ranges
            assert len(outgoing[0].ranges) == 2
            assert all(caller_text[r.start:r.end] == b'leaf' for r in outgoing[0].ranges)
            assert a.path(caller.target.fileId).endswith('/src/caller.cj')
            assert a.path(outgoing[0].item.target.fileId).endswith('/src/leaf.cj')
            assert a.incomingCalls(caller) == [] and a.outgoingCalls(leaf) == []
            assert a.prepareCallHierarchy('src/caller.cj', 0) == []
            group = HierarchyCalls(leaf, outgoing[0].ranges)
            assert group.item == leaf and group.ranges == outgoing[0].ranges
            diagnostic = InferenceDiagnostic.CustomAnnotationPlace(ExprId(3))
            assert diagnostic.field0 == ExprId(3)
            assert diagnostic == InferenceDiagnostic.CustomAnnotationPlace(ExprId(3))
            assert diagnostic != InferenceDiagnostic.CustomAnnotationPlace(ExprId(4))
            for offset in [-1, len(caller_text) + 1, caller_text.index('в'.encode()) + 1]:
                try:
                    a.prepareCallHierarchy('src/caller.cj', offset)
                except RuntimeError as error:
                    assert 'UTF-8 byte boundary' in str(error), str(error)
                else:
                    raise AssertionError('invalid call hierarchy offset was accepted')
            import builtins
            builtins._cjmcp_hierarchy = (a, caller)
            result = True
        """)
        self.assertTrue(response['result'])
        with (root / "src/leaf.cj").open('a', encoding='utf-8') as source:
            source.write('\n// new revision\n')
        stale = run("""
            import builtins
            old, entry = builtins._cjmcp_hierarchy
            for query in [old.incomingCalls, old.outgoingCalls]:
                try:
                    query(entry)
                except RuntimeError as error:
                    assert 'ContentModified' in str(error), str(error)
                else:
                    raise AssertionError('stale hierarchy query was accepted')
            del builtins._cjmcp_hierarchy
            result = True
        """)
        self.assertTrue(stale['result'])

    def _check_source_changes(self, run):
        # arrange - use the native change model through the embedded Python API.
        created = run("""
            a = workspace.analysis()
            text = 'package sample\\n// ё😀\\npublic func changeApi(): Int64 { 1 }\\n'
            change = SourceChange([FileChange.CreateFile('src/change_api.cj', text),
                                   FileChange.CreateFile('notes/nested/empty.txt', '')])
            assert change == SourceChange(change.files)
            assert change != SourceChange([])
            assert change.files[0] == FileChange.CreateFile('src/change_api.cj', text)
            report = workspace.applyChange(change, a.revision)
            assert isinstance(report, ApplyChangeResult)
            assert report.isSuccess and report.applied == [0, 1], report.error
            assert report.failed is None and report.error is None
            assert workspace.revision == a.revision == report.revision
            result = a.revision
        """)

        # act - native formatter edits can be passed straight to EditFile.
        edited = run("""
            a = workspace.analysis()
            before = a.text('src/change_api.cj')
            edits = a.formatting('src/change_api.cj')
            assert edits and all(isinstance(e, TextEdit) for e in edits)
            report = workspace.applyChange(SourceChange([
                FileChange.EditFile('src/change_api.cj', before, edits)]), a.revision)
            assert report.isSuccess, report.error
            assert a.text('src/change_api.cj') == before
            result = a.revision
        """)

        # assert - the next call sees the changed source, with no diagnostics.
        checked = run("""
            from pathlib import Path
            a = workspace.analysis()
            before = a.text('src/change_api.cj')
            assert '// ё😀' in before and '    1' in before
            assert workspace.diagnostics('src/change_api.cj') == []
            assert Path(workspace.root, 'notes/nested/empty.txt').read_bytes() == b''
            for change in [
                SourceChange([FileChange.CreateFile('untouched', ''),
                              FileChange.CreateFile('src/change_api.cj', 'bad')]),
                SourceChange([FileChange.CreateFile('untouched', ''),
                              FileChange.DeleteFile('src/change_api.cj', 'stale')]),
                SourceChange([FileChange.CreateFile('untouched', ''),
                              FileChange.CreateFile('src/../untouched', '')]),
                SourceChange([FileChange.CreateFile('../outside', '')]),
                SourceChange([FileChange.CreateFile('untouched', ''),
                              FileChange.EditFile('src/change_api.cj', before,
                                  [TextEdit(TextRange(before.encode().index('ё'.encode()) + 1,
                                                      before.encode().index('ё'.encode()) + 2), 'x')])]),
            ]:
                report = workspace.applyChange(change, a.revision)
                assert not report.isSuccess and report.applied == [] and report.failed is None
                assert not Path(workspace.root, 'untouched').exists()
            try:
                workspace.applyChange(SourceChange([]), a.revision - 1)
            except RuntimeError as error:
                assert 'ContentModified' in str(error)
            else:
                raise AssertionError('stale revision was accepted')
            # Disk changes during a script do not become valid by supplying the new disk text.
            path = Path(workspace.root, 'src/change_api.cj')
            path.write_bytes((before + '// external\\n').encode())
            report = workspace.applyChange(SourceChange([
                FileChange.DeleteFile('src/change_api.cj', before + '// external\\n')]), a.revision)
            assert not report.isSuccess and 'analysis revision' in report.error
            path.write_bytes(before.encode())
            report = workspace.applyChange(SourceChange([
                FileChange.RenameFile('src/change_api.cj', 'src/change_api_renamed.cj', before),
                FileChange.DeleteFile('notes/nested/empty.txt', '')]), a.revision)
            assert report.isSuccess and report.applied == [0, 1], report.error
            assert a.text('src/change_api.cj') == before
            result = a.revision
        """)
        self.assertGreater(edited['revision'], created['revision'])
        self.assertGreater(checked['revision'], edited['revision'])
        renamed = run("""
            a = workspace.analysis()
            assert any(p.endswith('/src/change_api_renamed.cj') for p in workspace.files())
            assert all(not p.endswith('/src/change_api.cj') for p in workspace.files())
            report = workspace.applyChange(SourceChange([FileChange.DeleteFile(
                'src/change_api_renamed.cj', a.text('src/change_api_renamed.cj'))]), a.revision)
            assert report.isSuccess, report.error
            result = a.revision
        """)
        self.assertGreater(renamed['revision'], checked['revision'])


    def _check_source_editing(self, run):
        # arrange - create and then edit UTF-8 source entirely inside runPython.
        created = run("""
            from pathlib import Path
            a = workspace.analysis()
            path = Path(workspace.root, 'src/tool_edit.cj')
            assert not path.exists()
            path.write_bytes('package sample\\n// привет\\npublic func toolEdit(): Int64 { 1 }\\n'.encode('utf-8'))
            result = a.revision
        """)

        # act - select the return literal within the declaration's byte range.
        edited = run("""
            from pathlib import Path
            a = workspace.analysis()
            path = 'src/tool_edit.cj'
            node = next(n for n in workspace.structure(path) if n.name == 'toolEdit')
            before = a.text(path).encode('utf-8')
            start = before.index(b'1', node.selectionRange.end, node.range.end)
            after = before[:start] + b'2' + before[start + 1:]
            target = Path(workspace.root, path)
            assert target.read_bytes() == before
            target.write_bytes(after)
            assert a.text(path).encode('utf-8') == before
            result = a.revision
        """)

        # assert - a later call observes the edit with a fresh analysis revision.
        checked = run("""
            from pathlib import Path
            a = workspace.analysis()
            assert '// привет' in a.text('src/tool_edit.cj')
            assert '{ 2 }' in a.text('src/tool_edit.cj')
            assert workspace.diagnostics('src/tool_edit.cj') == []
            Path(workspace.root, 'src/tool_edit.cj').unlink()
            result = a.revision
        """)
        self.assertGreater(edited['revision'], created['revision'])
        self.assertGreater(checked['revision'], edited['revision'])
        deleted = run("result = all(not p.endswith('/tool_edit.cj') for p in workspace.files())")
        self.assertTrue(deleted['result'])

    def _check_macros(self, root, run):
        # Expansion finishes before analysis() returns, including after a macro library changes.
        counter = root / "expansion-count"
        macro_dir = root / "src/ms"
        macro_dir.mkdir()
        macro_output = '''quote(public func generated(): Int64 { 41 }
          public class Generated {}
          public func greeting(): String { "привет" }
          public func typed(value: Generated): Generated { value })'''
        macro_source = """macro package sample.ms
import std.ast.*
public macro Emit(input: Tokens): Tokens {
    EMITTED_TOKENS
}
public macro Pass(input: Tokens): Tokens { input }
""".replace("EMITTED_TOKENS", macro_output)
        macro_source = macro_source.replace(
            "import std.ast.*", "import std.ast.*\nimport std.fs.File",
        ).replace(
            "    quote(",
            f'    File.appendTo({json.dumps(str(counter))}, "x".toArray())\n    quote(',
        )
        (macro_dir / "macros.cj").write_text(macro_source, encoding="utf-8", newline="\n")
        macro_use = """package sample
import sample.ms.*
import std.deriving.*
@Pass @Emit public func placeholder(): Int64 { 0 }
@Derive[Equatable] public struct Value { let n: Int64 = 1 }
main() { generated() }
"""
        (root / "src/main.cj").write_text(macro_use, encoding="utf-8", newline="\n")
        expanded = run(f"""
            from pathlib import Path
            workspace.reload()
            assert workspace.macros.state == MacroState.Settled() and not workspace.macros.diagnostics, workspace.macros
            assert workspace.loadDiagnostics == [], workspace.loadDiagnostics
            old = workspace.analysis()
            call = old.macroCall('src/main.cj', {macro_use.index('@Pass')})
            assert call is not None
            expansion = old.expansion(call.call)
            assert expansion.kind == ExpansionKind.ServerExpansion()
            assert 'generated' in expansion.text and '41' in expansion.text, expansion.text
            text = expansion.text.encode('utf-8')
            offset = text.rindex(b'value')
            hover = old.hoverInExpansion(call.call, offset)
            assert isinstance(hover, HoverResult) and hover.items
            assert text[hover.range.start:hover.range.end] == b'value'
            targets = old.definitionInExpansion(call.call, offset)
            assert targets and all(isinstance(t, NavigationTarget) for t in targets)
            for target in targets:
                target_text = (old.text(old.path(target.fileId)) if target.expansion is None
                               else old.expansion(target.expansion).text).encode('utf-8')
                # SDK output may attribute a generated token to the nested @Emit call.
                assert target_text[target.focusRange.start:target.focusRange.end] in [b'value', b'@Emit']
            types = old.typeDefinitionInExpansion(call.call, offset)
            assert types and all(isinstance(t, NavigationTarget) for t in types)
            for target in types:
                target_text = (old.text(old.path(target.fileId)) if target.expansion is None
                               else old.expansion(target.expansion).text).encode('utf-8')
                assert target_text[target.focusRange.start:target.focusRange.end] in [b'Generated', b'@Emit']
            bad_offsets = [-1, len(text) + 1, text.index('п'.encode()) + 1]
            for query in [old.hoverInExpansion, old.definitionInExpansion, old.typeDefinitionInExpansion]:
                for bad in bad_offsets:
                    try:
                        query(call.call, bad)
                    except RuntimeError as error:
                        assert 'UTF-8 byte boundary' in str(error), str(error)
                    else:
                        raise AssertionError('invalid expansion offset was accepted')
            assert old.newFilePackageLine('src/ms/new.cj') == 'macro package sample.ms'
            derive = old.macroCall('src/main.cj', {macro_use.index('@Derive')})
            assert old.expansion(derive.call).kind == ExpansionKind.ServerExpansion()
            assert workspace.diagnostics('src/main.cj') == [], [d.message for d in workspace.diagnostics('src/main.cj')]
            macro_path = Path(workspace.root) / 'src/ms/macros.cj'
            import os
            stamp = macro_path.stat()
            macro_path.write_text(macro_path.read_text().replace('{{ 41 }}', '{{ 42 }}'))
            os.utime(macro_path, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
            workspace.reload()
            assert workspace.macros.state == MacroState.Settled() and not workspace.macros.diagnostics, workspace.macros
            # Even reload cannot change the revision halfway through this script.
            current = workspace.analysis()
            current_call = current.macroCall('src/main.cj', {macro_use.index('@Pass')})
            assert '41' in current.expansion(current_call.call).text
            assert old.revision == current.revision == workspace.revision
            import builtins
            builtins._cjmcp_old_analysis = old
            result = workspace.macros.diagnostics
        """)
        self.assertEqual(expanded["result"], [])
        changed = run(f"""
            import builtins
            assert workspace.macros.state == MacroState.Settled() and not workspace.macros.diagnostics, workspace.macros
            current = workspace.analysis()
            current_call = current.macroCall('src/main.cj', {macro_use.index('@Pass')})
            assert '42' in current.expansion(current_call.call).text, current.expansion(current_call.call).text
            try:
                builtins._cjmcp_old_analysis.declarations('src/main.cj')
            except RuntimeError as error:
                assert 'ContentModified' in str(error), str(error)
            else:
                raise AssertionError('old analysis read the new revision')
            del builtins._cjmcp_old_analysis
            result = workspace.revision
        """)
        self.assertGreater(changed['revision'], expanded['revision'])
        self.assertEqual(changed['result'], changed['revision'])
        unchanged = run('result = workspace.macros')
        self.assertEqual(unchanged['result'], {'state': 'settled', 'diagnostics': []})
        self.assertEqual(unchanged['revision'], changed['revision'])

        count = counter.read_text()
        # A regular function edit must reuse existing expansions, not just compiler artifacts.
        with (root / "src/helper.cj").open("a", encoding="utf-8") as helper:
            helper.write("\npublic func unrelated(): Int64 { 7 }\n")
        regular_edit = run('result = workspace.macros')
        self.assertEqual(regular_edit['result'], {'state': 'settled', 'diagnostics': []})
        self.assertGreater(regular_edit['revision'], unchanged['revision'])
        self.assertEqual(counter.read_text(), count)

        # Observe expansion's side effect before issuing another tool call: the worker
        # must make progress while the stdio reader is idle, without a foreground reload.
        (macro_dir / "macros.cj").write_text(
            macro_source.replace('{ 41 }', '{ 43 }'), encoding="utf-8", newline="\n",
        )
        import time
        deadline = time.monotonic() + 30
        while counter.read_text() == count:
            self.assertLess(time.monotonic(), deadline, "background macro expansion never ran")
            time.sleep(0.01)
        background = run(f"""
            a = workspace.analysis()
            call = a.macroCall('src/main.cj', {macro_use.index('@Pass')})
            result = a.expansion(call.call).text
        """)
        self.assertIn('43', background['result'])
        self.assertGreater(background['revision'], regular_edit['revision'])

        # A macro exception is retained as an expansion problem, and a later reload can recover.
        (macro_dir / "macros.cj").write_text(
            macro_source.replace(macro_output,
                                 'throw Exception("expansion probe failed")'),
            encoding="utf-8", newline="\n",
        )
        failed_expansion = run("""
            assert workspace.macros.state == MacroState.Settled() and workspace.macros.diagnostics
            result = workspace.macros.diagnostics
        """)
        self.assertTrue(any(d['code'] == 'macro_expansion' and '@Emit failed' in d['message'] for d in failed_expansion["result"]),
                        failed_expansion)
        self.assertTrue(any('expansion probe failed' in d['message'] for d in failed_expansion["result"]),
                        failed_expansion)
        self.assertTrue(any(d['path'] == str(root / "src/main.cj") and d['line'] == 4 and d['column'] == 7
                            and d['range'] == {'start': macro_use.encode().index(b'@Emit'),
                                               'end': macro_use.encode().index(b'@Emit') + len(b'@Emit')}
                            for d in failed_expansion["result"]), failed_expansion)
        # Structured diagnostics retain source locations independently of worker stderr.

        # Build failure is visible without making a partially expanded revision look complete.
        (macro_dir / "macros.cj").write_text(
            macro_source.replace(macro_output, 'missingName'),
            encoding="utf-8", newline="\n",
        )
        failed_build = run("""
            assert workspace.macros.state == MacroState.Settled() and workspace.macros.diagnostics
            result = workspace.macros.diagnostics
        """)
        self.assertTrue(any(d['code'] == 'macro_build' and d['severity'] == 'error' for d in failed_build["result"]))
        self.assertTrue(any(d['code'] == 'macro_not_sent' for d in failed_build["result"]))
        (macro_dir / "macros.cj").write_text(macro_source, encoding="utf-8", newline="\n")
        recovered_macros = run("result = workspace.macros")
        self.assertEqual(recovered_macros["result"], {"state": "settled", "diagnostics": []})


if __name__ == "__main__":
    unittest.main()
