package cjls

import std.unittest.*
import std.unittest.testmacro.*
import stdxx.{IntegerOrString, Nullable}
import fjson.*
import jsonrpc.*
import cjls.lsp_types.*
import cjls.lsp_types.Range as LspRange

/*
 * The server's own path through the codec, envelope included: a frame's bytes to a handler's
 * params, and a handler's result to a frame's bytes. #9's messages: a keystroke's `didChange`, a
 * 64 KB `didOpen`, and the answer to `documentSymbol`, 550 symbols.
 *
 * `cjHeapSize=4GB cjpm bench '--filter=JsonCodecBench.*'`
 */

let BENCH_KEYSTROKE: Array<Byte> = ##"{"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"file:///home/user/project/src/main.cj","version":42},"contentChanges":[{"range":{"start":{"line":120,"character":17},"end":{"line":120,"character":17}},"rangeLength":0,"text":"a"}]}}"##.toArray()

// JSON string content, escapes included: quotes, backslashes, a tab, Cyrillic and an emoji
let BENCH_LINE = #"    let s = \"a \\\"quoted\\\" \\\\ path\tтекст 😀\"; // комментарий\n"#

let BENCH_OPEN: Array<Byte> = (##"{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///home/user/project/src/main.cj","languageId":"cangjie","version":1,"text":""## +
    BENCH_LINE * (65536 / BENCH_LINE.size) + ##""}}}"##).toArray()

func benchPosition(line: UInt32, character: UInt32): Position {
    Position(line: line, character: character)
}

let BENCH_SYMBOLS: Nullable<SymbolInformationsOrDocumentSymbols> = Nullable.Value(
    SymbolInformationsOrDocumentSymbols.AsDocumentSymbols(
        Array<DocumentSymbol>(50) {
            c =>
            let methods = Array<DocumentSymbol>(10) {
                m =>
                let line = UInt32(c * 100 + m * 9 + 1)
                DocumentSymbol(name: "method${m}OfClass${c}", detail: "(a: Int64, b: String): Unit", kind: SymbolKind.Method,
                    range: LspRange(start: benchPosition(line, 4), end: benchPosition(line + 7, 5)),
                    selectionRange: LspRange(start: benchPosition(line, 9), end: benchPosition(line, 20)))
            }
            let line = UInt32(c * 100)
            DocumentSymbol(name: "Class${c}", kind: SymbolKind.Class,
                range: LspRange(start: benchPosition(line, 0), end: benchPosition(line + 95, 1)),
                selectionRange: LspRange(start: benchPosition(line, 6), end: benchPosition(line, 12)), children: methods)
        }))

@Test
class JsonCodecBench {
    @Bench
    func readKeystroke(): DidChangeTextDocumentParams {
        let body = fromJsonBytes<Body>(BENCH_KEYSTROKE)
        DidChangeTextDocumentNotificationSpec().decodeParams(body.getNotificationBodyOrThrow().params)
    }

    @Bench
    func readOpen(): DidOpenTextDocumentParams {
        let body = fromJsonBytes<Body>(BENCH_OPEN)
        DidOpenTextDocumentNotificationSpec().decodeParams(body.getNotificationBodyOrThrow().params)
    }

    @Bench
    func writeSymbols(): Array<Byte> {
        let result = DocumentSymbolRequestSpec().encodeResult(BENCH_SYMBOLS)
        toJsonBytes(ResponseBody(Nullable.Value(IntegerOrString.Integer(7)), ResultOrError.Result(result)).enveloped())
    }
}
