package fjson

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

/*
 * `FjTapeB` (layout B, one Int64 a token) on the same decoders as `tape_bench_test.cj`, copied.
 *
 * `cjHeapSize=4GB cjpm bench --target-dir target/bench '--filter=FjTapeBBench.*'`
 */

/** The envelope in one pass, `params` decoded in place when `method` came first, else from their token. */
func tapeBRead<P>(t: FjTapeB, decode: (String, FjTapeB) -> P): (?Int64, P) {
    var method: ?String = None
    var id: ?Int64 = None
    var params: ?P = None
    var paramsAt: ?Int64 = None
    let end = t.beginObject()
    while (t.nextKey(end)) {
        if (t.keyIs("jsonrpc")) {
            if (t.readString() != "2.0") {
                throw FjException("not 2.0")
            }
        } else if (t.keyIs("id")) {
            id = t.readInt64()
        } else if (t.keyIs("method")) {
            method = t.readString()
        } else if (t.keyIs("params")) {
            match (method) {
                case Some(m) => params = decode(m, t)
                case None =>
                    paramsAt = t.position
                    t.skip()
            }
        } else {
            t.skip()
        }
    }
    match ((params, paramsAt)) {
        case (Some(p), _) => (id, p)
        case (None, Some(token)) =>
            t.seek(token)
            (id, decode(rpcRequired(method, "method"), t))
        case _ => throw FjException("no params")
    }
}

func tapeBPosition(t: FjTapeB): RpcPosition {
    var line: ?UInt32 = None
    var character: ?UInt32 = None
    let end = t.beginObject()
    while (t.nextKey(end)) {
        if (t.keyIs("line")) {
            line = t.readUInt32()
        } else if (t.keyIs("character")) {
            character = t.readUInt32()
        } else {
            t.skip()
        }
    }
    RpcPosition(rpcRequired(line, "line"), rpcRequired(character, "character"))
}

func tapeBRange(t: FjTapeB): RpcRange {
    var start: ?RpcPosition = None
    var end: ?RpcPosition = None
    let close = t.beginObject()
    while (t.nextKey(close)) {
        if (t.keyIs("start")) {
            start = tapeBPosition(t)
        } else if (t.keyIs("end")) {
            end = tapeBPosition(t)
        } else {
            t.skip()
        }
    }
    RpcRange(rpcRequired(start, "start"), rpcRequired(end, "end"))
}

/**
 * A change: the variant (partial or whole document) picked by the presence of `range` before the
 * value is read, as a derived untagged union over the tape would; then one read.
 */
func tapeBChange(t: FjTapeB): RpcChange {
    let partial = t.hasKey("range")
    var range: ?RpcRange = None
    var rangeLength: ?UInt32 = None
    var text: ?String = None
    let end = t.beginObject()
    while (t.nextKey(end)) {
        if (partial && t.keyIs("range")) {
            range = tapeBRange(t)
        } else if (partial && t.keyIs("rangeLength")) {
            rangeLength = t.readUInt32()
        } else if (t.keyIs("text")) {
            text = t.readString()
        } else {
            t.skip()
        }
    }
    RpcChange(range, rangeLength, rpcRequired(text, "text"))
}

func tapeBDidChange(_: String, t: FjTapeB): RpcDidChange {
    var uri: ?String = None
    var version: ?Int32 = None
    var changes: ?Array<RpcChange> = None
    let end = t.beginObject()
    while (t.nextKey(end)) {
        if (t.keyIs("textDocument")) {
            let close = t.beginObject()
            while (t.nextKey(close)) {
                if (t.keyIs("uri")) {
                    uri = t.readString()
                } else if (t.keyIs("version")) {
                    version = t.readInt32()
                } else {
                    t.skip()
                }
            }
        } else if (t.keyIs("contentChanges")) {
            let list = ArrayList<RpcChange>()
            let close = t.beginArray()
            while (t.nextItem(close)) {
                list.add(tapeBChange(t))
            }
            changes = list.toArray()
        } else {
            t.skip()
        }
    }
    RpcDidChange(rpcRequired(uri, "uri"), rpcRequired(version, "version"), rpcRequired(changes, "contentChanges"))
}

func tapeBSymbolParams(_: String, t: FjTapeB): String {
    var uri: ?String = None
    let end = t.beginObject()
    while (t.nextKey(end)) {
        if (t.keyIs("textDocument")) {
            let close = t.beginObject()
            while (t.nextKey(close)) {
                if (t.keyIs("uri")) {
                    uri = t.readString()
                } else {
                    t.skip()
                }
            }
        } else {
            t.skip()
        }
    }
    rpcRequired(uri, "uri")
}

/** The text of a `didOpen`, as `fjsonText` reads it. */
func tapeBText(t: FjTapeB): String {
    var text = ""
    let end = t.beginObject()
    while (t.nextKey(end)) {
        if (t.keyIs("params")) {
            let params = t.beginObject()
            while (t.nextKey(params)) {
                if (t.keyIs("textDocument")) {
                    let document = t.beginObject()
                    while (t.nextKey(document)) {
                        if (t.keyIs("text")) {
                            text = t.readString()
                        } else {
                            t.skip()
                        }
                    }
                } else {
                    t.skip()
                }
            }
        } else {
            t.skip()
        }
    }
    text
}

let TAPE_B = FjTapeB()

@Test
@Configure[warmup: 1 * Duration.second, minDuration: 3 * Duration.second]
class FjTapeBBench {
    @Bench
    func indexKeystroke(): Unit {
        TAPE_B.index(KEYSTROKE)
        rpcSink += TAPE_B.size
    }

    @Bench
    func readKeystroke(): Unit {
        TAPE_B.index(KEYSTROKE)
        rpcSink += tapeBRead(TAPE_B, tapeBDidChange)[1].changes.size
    }

    @Bench
    func indexSymbolRequest(): Unit {
        TAPE_B.index(SYMBOL_REQUEST)
        rpcSink += TAPE_B.size
    }

    @Bench
    func readSymbolRequest(): Unit {
        TAPE_B.index(SYMBOL_REQUEST)
        rpcSink += tapeBRead(TAPE_B, tapeBSymbolParams)[1].size
    }

    @Bench
    func indexDidOpen64Kb(): Unit {
        TAPE_B.index(DID_OPEN)
        rpcSink += TAPE_B.size
    }

    @Bench
    func readDidOpen64Kb(): Unit {
        TAPE_B.index(DID_OPEN)
        rpcSink += tapeBText(TAPE_B).size
    }
}
