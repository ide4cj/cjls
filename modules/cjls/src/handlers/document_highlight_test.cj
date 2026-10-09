package cjls.handlers

import std.fs.Path
import std.unittest.*
import std.unittest.testmacro.*
import stdxx.Nullable
import cjls.lsp_types.*
import cjls.server.*

func highlightsOf(state: ServerState, path: Path, line: UInt32, character: UInt32): Nullable<Array<DocumentHighlight>> {
    handleDocumentHighlight(state.snapshot(), DocumentHighlightParams(
        textDocument: TextDocumentIdentifier(uri: uriOf(path)), position: Position(line: line, character: character)))
}

@Test
class DocumentHighlightTest {
    @TestCase
    func eachNameIsItsRangeInTheColumnsAgreedOnAndItsKind() {
        // arrange - the emoji is two UTF-16 units and four bytes
        let (state, dir) = loaded([("a.cj", "func f(): String {\n    var s = \"😀\"; s = s\n    s\n}\n")])

        // act
        let answer = highlightsOf(state, dir.join("a.cj"), 2, 4)

        // assert: the `var` written at its declaration, then written, read, read
        let highlights = match (answer) {
            case Nullable.Value(highlights) => highlights
            case _ => throw AssertException("no highlights")
        }
        @Expect(highlights.map {one => "${at(one.range.start)}-${at(one.range.end)}"},
            ["1:8-1:9", "1:18-1:19", "1:22-1:23", "2:4-2:5"])
        @Expect(highlights.map {
            one => match (one.kind) {
                case Some(DocumentHighlightKind.Write) => "write"
                case Some(DocumentHighlightKind.Read) => "read"
                case _ => "text"
            }
        }, ["write", "write", "read", "read"])
    }

    @TestCase
    func aNameNothingResolvesIsNull() {
        // arrange
        let (state, dir) = loaded([("a.cj", "func f(): Unit {\n    nothing\n}\n")])

        // act
        let answer = highlightsOf(state, dir.join("a.cj"), 1, 4)

        // assert
        @Expect(answer.isNull())
    }
}
