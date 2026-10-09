package fjson

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*

/*
 * The tape (`FjTape`) against the pull reader on `FjRpcBench`'s messages, decoded by hand the way a
 * generator would, both sides in one binary: `index*` is the tape alone, `read*` the tape and the
 * typed read, `pull*` the same decode on `FjReader` (`FjRpcBench`'s, repeated here so that the two
 * sides share a run). A difference between `pull*` here and `FjRpcBench` is the binary's layout.
 *
 * `cjHeapSize=4GB cjpm bench --target-dir target/bench '--filter=FjTapeBench.*'`
 */

/** The envelope in one pass, `params` decoded in place when `method` came first, else from their token. */
func tapeRead<P>(t: FjTape, decode: (String, FjTape) -> P): (?Int64, P) {
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

func tapePosition(t: FjTape): RpcPosition {
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

func tapeRange(t: FjTape): RpcRange {
    var start: ?RpcPosition = None
    var end: ?RpcPosition = None
    let close = t.beginObject()
    while (t.nextKey(close)) {
        if (t.keyIs("start")) {
            start = tapePosition(t)
        } else if (t.keyIs("end")) {
            end = tapePosition(t)
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
func tapeChange(t: FjTape): RpcChange {
    let partial = t.hasKey("range")
    var range: ?RpcRange = None
    var rangeLength: ?UInt32 = None
    var text: ?String = None
    let end = t.beginObject()
    while (t.nextKey(end)) {
        if (partial && t.keyIs("range")) {
            range = tapeRange(t)
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

func tapeDidChange(_: String, t: FjTape): RpcDidChange {
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
                list.add(tapeChange(t))
            }
            changes = list.toArray()
        } else {
            t.skip()
        }
    }
    RpcDidChange(rpcRequired(uri, "uri"), rpcRequired(version, "version"), rpcRequired(changes, "contentChanges"))
}

func tapeSymbolParams(_: String, t: FjTape): String {
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
func tapeText(t: FjTape): String {
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

let TAPE = FjTape()
let TAPE_READER = FjReader(Array<Byte>())

@Test
@Configure[warmup: 1 * Duration.second, minDuration: 3 * Duration.second]
class FjTapeBench {
    @Bench
    func indexKeystroke(): Unit {
        TAPE.index(KEYSTROKE)
        rpcSink += TAPE.size
    }

    @Bench
    func readKeystroke(): Unit {
        TAPE.index(KEYSTROKE)
        rpcSink += tapeRead(TAPE, tapeDidChange)[1].changes.size
    }

    @Bench
    func pullKeystroke(): Unit {
        TAPE_READER.reset(KEYSTROKE)
        rpcSink += rpcRead(TAPE_READER, rpcDidChange)[1].changes.size
    }

    @Bench
    func indexSymbolRequest(): Unit {
        TAPE.index(SYMBOL_REQUEST)
        rpcSink += TAPE.size
    }

    @Bench
    func readSymbolRequest(): Unit {
        TAPE.index(SYMBOL_REQUEST)
        rpcSink += tapeRead(TAPE, tapeSymbolParams)[1].size
    }

    @Bench
    func pullSymbolRequest(): Unit {
        TAPE_READER.reset(SYMBOL_REQUEST)
        rpcSink += rpcRead(TAPE_READER, rpcSymbolParams)[1].size
    }

    @Bench
    func indexDidOpen64Kb(): Unit {
        TAPE.index(DID_OPEN)
        rpcSink += TAPE.size
    }

    @Bench
    func readDidOpen64Kb(): Unit {
        TAPE.index(DID_OPEN)
        rpcSink += tapeText(TAPE).size
    }

    @Bench
    func pullDidOpen64Kb(): Unit {
        TAPE_READER.reset(DID_OPEN)
        rpcSink += fjsonText(TAPE_READER).size
    }
}

@Test
@Measure[Runtime(AllocatedMemory)]
@Configure[warmup: 100, minDuration: 1 * Duration.second]
class FjTapeAllocationBench {
    @Bench
    func indexKeystroke(): Unit {
        TAPE.index(KEYSTROKE)
        rpcSink += TAPE.size
    }

    @Bench
    func readKeystroke(): Unit {
        TAPE.index(KEYSTROKE)
        rpcSink += tapeRead(TAPE, tapeDidChange)[1].changes.size
    }

    @Bench
    func pullKeystroke(): Unit {
        TAPE_READER.reset(KEYSTROKE)
        rpcSink += rpcRead(TAPE_READER, rpcDidChange)[1].changes.size
    }

    @Bench
    func readDidOpen64Kb(): Unit {
        TAPE.index(DID_OPEN)
        rpcSink += tapeText(TAPE).size
    }

    @Bench
    func pullDidOpen64Kb(): Unit {
        TAPE_READER.reset(DID_OPEN)
        rpcSink += fjsonText(TAPE_READER).size
    }
}
