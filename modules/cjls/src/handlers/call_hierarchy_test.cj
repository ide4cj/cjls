package cjls.handlers

import std.fs.Path
import std.unittest.*
import std.unittest.testmacro.*
import stdxx.Nullable
import cjls.lsp_types.*
import cjls.server.*

private func prepareHierarchy(
    state: ServerState,
    path: Path,
    character: UInt32
): Array<CallHierarchyItem> {
    match (
        handlePrepareCallHierarchy(
            state.snapshot(),
            CallHierarchyPrepareParams(
                textDocument: TextDocumentIdentifier(uri: uriOf(path)),
                position: Position(line: 1, character: character)
            )
        )
    ) {
        case Nullable.Value(items) => items
        case _ => throw AssertException("no hierarchy")
    }
}

@Test
class CallHierarchyHandlerTest {
    @TestCase
    func roundTripsItemsAndUsesTheCallersUtf16Ranges() {
        // arrange
        let (state, dir) =
            loaded(
                [
                    ("a.cj", "package m\nfunc target(): Unit {}\n"),
                    ("b.cj", "package m\n/* 😀 */ func caller(): Unit { target(); target() }\n")
                ]
            )
        let target = prepareHierarchy(state, dir.join("a.cj"), 5)[0]
        let caller = prepareHierarchy(state, dir.join("b.cj"), 14)[0]

        // act
        let incoming =
            handleIncomingCalls(state.snapshot(), CallHierarchyIncomingCallsParams(item: target))
        let outgoing =
            handleOutgoingCalls(state.snapshot(), CallHierarchyOutgoingCallsParams(item: caller))

        // assert
        @Expect(target.kind, SymbolKind.Function)
        @Expect(at(target.selectionRange.start), "1:5")
        @Expect(at(caller.selectionRange.start), "1:14")
        match (incoming) {
            case Nullable.Value(calls) =>
                @Expect(calls.size, 1)
                @Expect(calls[0].from.uri, caller.uri)
                @Expect(calls[0].from.name, "caller")
                @Expect(calls[0].fromRanges.map { range => at(range.start) }, ["1:31", "1:41"])
                @Expect(calls[0].fromRanges.map { range => at(range.end) }, ["1:37", "1:47"])
            case _ => @Fail("no incoming calls")
        }
        match (outgoing) {
            case Nullable.Value(calls) =>
                @Expect(calls.size, 1)
                @Expect(calls[0].to.uri, target.uri)
                @Expect(calls[0].to.name, "target")
                @Expect(calls[0].fromRanges.map { range => at(range.start) }, ["1:31", "1:41"])
            case _ => @Fail("no outgoing calls")
        }
    }

    @TestCase
    func aLeafReturnsAnEmptyArrayAndAnUnknownDocumentReturnsNull() {
        // arrange
        let (state, dir) = loaded([("a.cj", "package m\nfunc leaf(): Unit {}\n")])
        let leaf = prepareHierarchy(state, dir.join("a.cj"), 5)[0]

        // act
        let outgoing =
            handleOutgoingCalls(state.snapshot(), CallHierarchyOutgoingCallsParams(item: leaf))
        let unknown =
            handlePrepareCallHierarchy(
                state.snapshot(),
                CallHierarchyPrepareParams(
                    textDocument: TextDocumentIdentifier(uri: uriOf(dir.join("missing.cj"))),
                    position: Position(line: 0, character: 0)
                )
            )
        let renamed =
            CallHierarchyItem(
                name: "missing",
                kind: leaf.kind,
                uri: leaf.uri,
                range: leaf.range,
                selectionRange: leaf.selectionRange
            )
        let stale =
            handleIncomingCalls(state.snapshot(), CallHierarchyIncomingCallsParams(item: renamed))

        // assert
        match (outgoing) {
            case Nullable.Value(calls) => @Expect(calls.isEmpty())
            case _ => @Fail("a known leaf must have an empty result")
        }
        @Expect(unknown.isNull())
        @Expect(stale.isNull())
    }
}
