package cjls

import std.collection.HashMap
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

let BENCH_KEYSTROKE_PARAMS: ?RawJson = fromJsonBytes<Body>(BENCH_KEYSTROKE).getNotificationBodyOrThrow().params

let BENCH_KEYSTROKE_PARAMS_BYTES: Array<Byte> = (BENCH_KEYSTROKE_PARAMS ?? RawJson.NULL).bytes

// kept from message to message, as the transport keeps its own
let BENCH_READER = FjReader(Array<Byte>())

// the route's readers of params in place, one per method, as `Router` keeps them (D70)
let BENCH_PARAMS_READERS: HashMap<String, (FjReader) -> Any> = HashMap<String, (FjReader) -> Any>(
    [(DidChangeTextDocumentNotificationSpec.METHOD, {
        r =>
        let params: Any = DidChangeTextDocumentNotificationSpec().decodeParams(r)
        params
    })])

let BENCH_PARAMS_READER: (String) -> Option<(FjReader) -> Any> = {method => BENCH_PARAMS_READERS.get(method)}

/** The server's path since D70: the envelope read with the params in place, the route taking them decoded. */
func keystrokeReadInPlace(): DidChangeTextDocumentParams {
    BENCH_READER.reset(BENCH_KEYSTROKE)
    let (body, decoded) = Body.read(BENCH_READER, BENCH_PARAMS_READER)
    let note = body.getNotificationBodyOrThrow()
    let typed: ?DidChangeTextDocumentParams = match (decoded) {
        case Some(value) => value as DidChangeTextDocumentParams
        case None => None
    }
    typed ?? DidChangeTextDocumentNotificationSpec().decodeParams(note.params)
}

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

    // the two passes of `readKeystroke` apart: the envelope's, skipping `params` into a slice, and the route's
    @Bench
    func readKeystrokeEnvelope(): Body {
        fromJsonBytes<Body>(BENCH_KEYSTROKE)
    }

    @Bench
    func readKeystrokeParams(): DidChangeTextDocumentParams {
        DidChangeTextDocumentNotificationSpec().decodeParams(BENCH_KEYSTROKE_PARAMS)
    }

    // the pieces of those two passes: what the envelope pays to skip `params`, what a fresh reader
    // costs against the kept one, and the ceiling of reading `params` in place as `method` is known
    @Bench
    func skipKeystrokeParams(): Unit {
        BENCH_READER.reset(BENCH_KEYSTROKE_PARAMS_BYTES)
        BENCH_READER.skipValue()
    }

    @Bench
    func readKeystrokeEnvelopeOnKeptReader(): Body {
        BENCH_READER.reset(BENCH_KEYSTROKE)
        Body.fromJson(BENCH_READER)
    }

    @Bench
    func readKeystrokeParamsOnKeptReader(): DidChangeTextDocumentParams {
        BENCH_READER.reset(BENCH_KEYSTROKE_PARAMS_BYTES)
        DidChangeTextDocumentParams.fromJson(BENCH_READER)
    }

    @Bench
    func readKeystrokeInPlaceCeiling(): DidChangeTextDocumentParams {
        BENCH_READER.reset(BENCH_KEYSTROKE)
        var params: ?DidChangeTextDocumentParams = None
        BENCH_READER.beginObject()
        while (BENCH_READER.nextKey()) {
            if (BENCH_READER.keyIs("params")) {
                params = DidChangeTextDocumentParams.fromJson(BENCH_READER)
            } else if (BENCH_READER.keyIs("method")) {
                BENCH_READER.readString()
            } else {
                BENCH_READER.skipValue()
            }
        }
        params.getOrThrow()
    }

    @Bench
    func readKeystrokeInPlace(): DidChangeTextDocumentParams {
        keystrokeReadInPlace()
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

@Test
@Measure[Runtime(AllocatedMemory)]
@Configure[warmup: 100, minDuration: 1 * Duration.second]
class JsonCodecAllocationBench {
    @Bench
    func readKeystroke(): DidChangeTextDocumentParams {
        let body = fromJsonBytes<Body>(BENCH_KEYSTROKE)
        DidChangeTextDocumentNotificationSpec().decodeParams(body.getNotificationBodyOrThrow().params)
    }

    @Bench
    func readKeystrokeInPlace(): DidChangeTextDocumentParams {
        keystrokeReadInPlace()
    }

    @Bench
    func readKeystrokeEnvelopeOnKeptReader(): Body {
        BENCH_READER.reset(BENCH_KEYSTROKE)
        Body.fromJson(BENCH_READER)
    }

    @Bench
    func readKeystrokeParams(): DidChangeTextDocumentParams {
        DidChangeTextDocumentNotificationSpec().decodeParams(BENCH_KEYSTROKE_PARAMS)
    }

    @Bench
    func readKeystrokeParamsOnKeptReader(): DidChangeTextDocumentParams {
        BENCH_READER.reset(BENCH_KEYSTROKE_PARAMS_BYTES)
        DidChangeTextDocumentParams.fromJson(BENCH_READER)
    }
}
