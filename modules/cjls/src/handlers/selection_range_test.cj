package cjls.handlers

import std.collection.ArrayList
import std.unittest.*
import std.unittest.testmacro.*
import stdxx.Nullable
import rope.Encoding
import cjls.lsp_types.*
import cjls.server.*

func selectionRanges(state: ServerState, uri: String, positions: Array<Position>): ?Array<SelectionRange> {
    match (handleSelectionRange(state.snapshot(),
        SelectionRangeParams(textDocument: TextDocumentIdentifier(uri: uri), positions: positions))) {
        case Nullable.Value(ranges) => ranges
        case Nullable.Null => None
    }
}

/**
 * The ranges of a chain, innermost first, as `line:column-line:column`.
 */
func chainOf(selection: SelectionRange): Array<String> {
    let chain = ArrayList<String>()
    var current = Some(selection)
    while (let Some(it) <- current) {
        let range = it.range
        chain.add("${range.start.line}:${range.start.character}-${range.end.line}:${range.end.character}")
        current = it.parent
    }
    chain.toArray()
}

@Test
class SelectionRangeTest {
    /**
     * `(encoding, column of ab)`: the emoji is four bytes and two UTF-16 units.
     */
    @TestCase[row in [(Encoding.Utf8, UInt32(17)), (Encoding.Utf16, UInt32(15))]]
    func theChainIsInTheColumnsAgreedOn(row: (Encoding, UInt32)) {
        // arrange
        let (encoding, column) = row
        let state = opened("let s = \"😀\" + ab\n")
        state.encoding = encoding

        // act
        let ranges = selectionRanges(state, URI, [Position(line: 0, character: column + 1)]).getOrThrow()

        // assert - `ab`, the sum, the declaration, the file
        @Expect(ranges.size, 1)
        @Expect(chainOf(ranges[0]),
            ["0:${column}-0:${column + 2}", "0:8-0:${column + 2}", "0:0-0:${column + 2}", "0:0-1:0"])
    }

    @TestCase
    func eachPositionIsAnsweredInTheOrderAsked() {
        // arrange
        let state = opened("let a = 1\nlet b = 2\n")

        // act
        let ranges = selectionRanges(state, URI, [Position(line: 1, character: 4), Position(line: 0, character: 4)])
            .getOrThrow()

        // assert
        @Expect(ranges.map {range => chainOf(range)[0]}, ["1:4-1:5", "0:4-0:5"])
    }

    @TestCase
    func aPositionPastTheEndStandsForTheEnd() {
        // arrange
        let state = opened("let a = 1")

        // act
        let ranges = selectionRanges(state, URI, [Position(line: 7, character: 0)]).getOrThrow()

        // assert - the end is right after the `1`
        @Expect(chainOf(ranges[0]), ["0:8-0:9", "0:0-0:9"])
    }

    @TestCase
    func aDocumentTheServerDoesNotKnowHasNoSelections() {
        // act, assert
        @Expect(selectionRanges(ServerState(), URI, [Position(line: 0, character: 0)]).isNone())
    }
}
