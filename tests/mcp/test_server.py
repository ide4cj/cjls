"""Drive embedded Python through the real MCP process, with stdin kept open."""

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

ROOT = Path(__file__).resolve().parents[2]
BINARY = os.environ.get("CJMCP_BIN", str(ROOT / "target/release/bin/cjmcp"))


@unittest.skipUnless(sys.platform.startswith("linux"), "embedded CPython experiment supports native Linux")
class McpStdioTest(unittest.TestCase):
    def test_python_native_objects_errors_output_and_reload(self):
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
            process = subprocess.Popen(
                [BINARY, "--dir", str(root)], stdin=subprocess.PIPE,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                env={**os.environ, "cjHeapSize": "2GB"},
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
                self.assertIsNotNone(raw, "server closed stdout")
                reply = json.loads(raw)
                self.assertEqual(reply["id"], next_id)
                self.assertNotIn("error", reply)
                return reply["result"]

            def run(code, *, error=False):
                result = rpc("tools/call", {
                    "name": "runPython", "arguments": {"code": textwrap.dedent(code)},
                })
                self.assertEqual(result["isError"], error, result)
                self.assertEqual(json.loads(result["content"][0]["text"]), result["structuredContent"])
                return result["structuredContent"]

            try:
                # act - one Python call traverses native analysis objects from several queries
                initialization = rpc("initialize", {
                    "protocolVersion": "2025-11-25", "capabilities": {},
                    "clientInfo": {"name": "test", "version": "1"},
                })
                process.stdin.write(b'{"jsonrpc":"2.0","method":"notifications/initialized"}\n')
                process.stdin.flush()
                tools = rpc("tools/list")["tools"]
                native = run(f"""
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
                    result = {{
                        'files': workspace.files(),
                        'symbols': [node.name for node in nodes],
                        'hover': hover.items[0].code,
                        'target': location.path,
                        'problems': workspace.problems,
                        'macrosExpanded': workspace.macrosExpanded,
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
                self.assertFalse(data["macrosExpanded"])
                self.assertIn("прямые объекты loupe", native["stdout"])

                # act - inspect generic inference and its HIR, then navigate the selected callee
                inference = run(f"""
                    analysis = workspace.analysis()
                    defs = analysis.declarations('src/main.cj')
                    answer = next(d for d in defs if 'answer' in analysis.item(d).names)
                    assert isinstance(answer, DefId)
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
                    assert analysis.typeKind(inferred.locals[local]) == TyKind.PrimTy('Int64')
                    assert isinstance(analysis.typeKind(inferred.locals[local]), TyKind.PrimTy)
                    assert analysis.typeKind(inferred.locals[local]).field0 == 'Int64'
                    match analysis.typeKind(inferred.locals[local]):
                        case TyKind.PrimTy(name):
                            assert name == 'Int64'
                        case _:
                            raise AssertionError('inferred enum lost its variant')
                    assert analysis.typeText(analysis.internType(TyKind.PrimTy('Bool'))) == 'Bool'
                    assert not analysis.typeUnknown(inferred.locals[local])
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
                    # Retained revision remains self-consistent when reload creates a new database.
                    workspace.reload()
                    assert analysis.typeText(analysis.infer(answer).locals[local]) == 'Int64'
                    result = names
                """)
                self.assertIn("identity", inference["result"])

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
                invalid_offset = run(
                    f"workspace.hover('src/main.cj', {source.encode().index('п'.encode()) + 1})", error=True,
                )
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
                self.assertIn("UTF-8", invalid_offset["error"])
                self.assertEqual(recovered["result"], 42)

                # act - the same live workspace sees disk changes only after an explicit reload
                (root / "src/main.cj").write_text(
                    "package sample\nmain() { let value: Int64 = true }\n", encoding="utf-8", newline="\n",
                )
                (root / "src/new.cj").write_text(
                    "package sample\npublic func added() {}\n", encoding="utf-8", newline="\n",
                )
                stale = run("result = [node.name for node in workspace.structure('src/main.cj')]")
                changed = run("""
                    workspace.reload()
                    diagnostics = workspace.diagnostics('src/main.cj')
                    assert all(isinstance(item, Diagnostic) for item in diagnostics)
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
                        diagnostics=[item.message for item in diagnostics],
                        added=[node.name for node in workspace.structure('src/new.cj')])
                """)
                (root / "src/new.cj").unlink()
                after_delete = run("workspace.reload()\nresult = workspace.files()")

                # assert
                self.assertIn("answer", stale["result"])
                self.assertTrue(any("mismatched types" in message for message in changed["result"]["diagnostics"]))
                self.assertIn("added", changed["result"]["added"])
                self.assertNotIn(str(root / "src/new.cj"), after_delete["result"])
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
            self.assertEqual(process.returncode, 0, stderr)


if __name__ == "__main__":
    unittest.main()
