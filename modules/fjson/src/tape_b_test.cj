package fjson

import std.unittest.*
import std.unittest.testmacro.*

@Test
class FjTapeBTest {
    private func tape(text: String): FjTapeB {
        let t = FjTapeB()
        t.index(text.toArray())
        t
    }

    @TestCase
    func theKeystrokeReadsAsThePullReaderReadsIt() {
        // act
        let (_, pull) = rpcRead(FjReader(KEYSTROKE), rpcDidChange)
        let t = FjTapeB()
        t.index(KEYSTROKE)
        let (id, change) = tapeBRead(t, tapeBDidChange)

        // assert
        @Expect(id.isNone())
        @Expect(change.uri, pull.uri)
        @Expect(change.version, pull.version)
        @Expect(change.changes.size, pull.changes.size)
        @Expect(change.changes[0].text, pull.changes[0].text)
        @Expect(change.changes[0].rangeLength, pull.changes[0].rangeLength)
        @Expect(change.changes[0].range?.start.line, pull.changes[0].range?.start.line)
        @Expect(change.changes[0].range?.start.character, pull.changes[0].range?.start.character)
        @Expect(change.changes[0].range?.end.line, pull.changes[0].range?.end.line)
        @Expect(change.changes[0].range?.end.character, pull.changes[0].range?.end.character)
    }

    @TestCase
    func theSymbolRequestAndTheDidOpenReadAsThePullReaderReadsThem() {
        // act
        let t = FjTapeB()
        t.index(SYMBOL_REQUEST)
        let (id, uri) = tapeBRead(t, tapeBSymbolParams)
        t.index(DID_OPEN)
        let text = tapeBText(t)

        // assert
        @Expect(id, Some(7))
        @Expect(uri, "file:///home/user/project/src/main.cj")
        @Expect(text, fjsonText(FjReader(DID_OPEN)))
    }

    @TestCase
    func paramsBeforeMethodAreReadFromTheirToken() {
        // arrange
        let t = tape(##"{"params":{"textDocument":{"uri":"file:///x.cj"}},"jsonrpc":"2.0","id":3,"method":"textDocument/documentSymbol"}"##)

        // act
        let (id, uri) = tapeBRead(t, tapeBSymbolParams)

        // assert
        @Expect(id, Some(3))
        @Expect(uri, "file:///x.cj")
    }

    @TestCase
    func aWholeDocumentChangeIsTheOtherVariant() {
        // arrange
        let t = tape(##"{"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"file:///x.cj","version":2},"contentChanges":[{"text":"all of it"}]}}"##)

        // act
        let (_, change) = tapeBRead(t, tapeBDidChange)

        // assert
        @Expect(change.changes[0].range.isNone())
        @Expect(change.changes[0].text, "all of it")
    }

    @TestCase
    func hasKeySeesTheObjectsOwnKeysAndNotItsChildrens() {
        // arrange
        let t = tape(#"{"a": {"range": 1, "deep": [1, [2]]}, "b": 2, "c": "range"}"#)

        // act & assert
        @Expect(t.hasKey("a"))
        @Expect(t.hasKey("b"))
        @Expect(t.hasKey("c"))
        @Expect(!t.hasKey("range"))
        @Expect(!t.hasKey("deep"))
        let end = t.beginObject()
        @Expect(t.nextKey(end))
        @Expect(t.hasKey("range"))
        @Expect(!t.hasKey("a"))
    }

    @TestCase
    func escapedKeysAndStringsAreUnescapedAndTheRestKeepsItsPlace() {
        // arrange
        let t = tape(#"{"key": "x\ny \"q\" 😀", "n": -42, "s": "plain", "t": true, "z": null}"#)

        // act
        let end = t.beginObject()
        @Expect(t.nextKey(end))
        @Expect(t.keyIs("key"))
        let s = t.readString()
        @Expect(t.nextKey(end))
        @Expect(t.keyIs("n"))
        let n = t.readInt64()
        @Expect(t.nextKey(end))
        let plain = t.readString()
        @Expect(t.nextKey(end))
        let b = t.readBool()
        @Expect(t.nextKey(end))
        @Expect(t.isNull())
        t.readNull()

        // assert
        @Expect(!t.nextKey(end))
        @Expect(s, "x\ny \"q\" 😀")
        @Expect(n, -42)
        @Expect(plain, "plain")
        @Expect(b)
    }

    @TestCase
    func skipStepsOverAValueOfAnySize() {
        // arrange
        let t = tape(#"[{"a": [1, 2, {"b": [[], {}]}]}, "x", [3], 4]"#)

        // act
        let end = t.beginArray()
        t.skip()
        let x = t.readString()
        t.skip()
        let four = t.readInt64()

        // assert
        @Expect(!t.nextItem(end))
        @Expect(x, "x")
        @Expect(four, 4)
    }

    @TestCase
    func rawValueIsTheValuesOwnBytes() {
        // arrange
        let t = tape(#"{"params": {"a": [1, "}", {"b": null}] } , "method": "m"}"#)

        // act
        let end = t.beginObject()
        t.nextKey(end)
        let raw = t.rawValue()
        t.nextKey(end)
        let method = t.readString()

        // assert
        @Expect(String.fromUtf8(raw), #"{"a": [1, "}", {"b": null}] }"#)
        @Expect(method, "m")
    }

    @TestCase
    func whatIsNotJsonIsRefusedAtIndexTime() {
        // act & assert
        @AssertThrows[FjException](tape(#"{"a": 1,}"#))
        @AssertThrows[FjException](tape(#"{"a" 1}"#))
        @AssertThrows[FjException](tape(#"[1 2]"#))
        @AssertThrows[FjException](tape(#"{"a": 1]"#))
        @AssertThrows[FjException](tape(#"["unterminated"#))
        @AssertThrows[FjException](tape(#"["bad \x escape"]"#))
        @AssertThrows[FjException](tape(#"[01]"#))
        @AssertThrows[FjException](tape(#"[1.]"#))
        @AssertThrows[FjException](tape(#"[tru]"#))
        @AssertThrows[FjException](tape(#"[1] 2"#))
        @AssertThrows[FjException](tape(""))
        @AssertThrows[FjException](tape("[\"\u{01}\"]"))
    }

    @TestCase
    func aNumberOutsideItsTypeThrowsOnRead() {
        // arrange
        let t = tape("[5000000000, 1.5, -1]")
        let end = t.beginArray()

        // act & assert
        @Expect(t.readInt64(), 5_000_000_000)
        @AssertThrows[FjException](t.readInt64())
        t.skip()
        // the range is checked after the token was taken
        @AssertThrows[FjException](t.readUInt32())
        @Expect(!t.nextItem(end))
    }

    @TestCase
    func theTapeIsReusedAcrossMessages() {
        // arrange
        let t = FjTapeB()
        t.index(DID_OPEN)
        let tokens = t.size

        // act
        t.index(KEYSTROKE)
        let (_, change) = tapeBRead(t, tapeBDidChange)
        t.index(DID_OPEN)

        // assert
        @Expect(change.version, 42)
        @Expect(t.size, tokens)
    }
}
