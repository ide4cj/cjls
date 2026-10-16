package cjls.handlers

import std.unittest.*
import std.unittest.testmacro.*
import stdx.log.NoopLogger
import cjls.lsp_types.*
import cjls.server.*

func pulled(snap: ServerSnapshot, uri!: String = URI): Array<Diagnostic> {
    fullReport(snap, None<String>).items
}

/**
 * The full report a pull with `previousResultId` answers; it fails on an `unchanged` one.
 */
func fullReport(snap: ServerSnapshot, previousResultId: ?String): RelatedFullDocumentDiagnosticReport {
    let params = DocumentDiagnosticParams(textDocument: TextDocumentIdentifier(uri: URI),
        previousResultId: previousResultId)
    match (handleDocumentDiagnostic(snap, params)) {
        case DocumentDiagnosticReport.AsRelatedFullDocumentDiagnosticReport(report) => report
        case _ => throw AssertException("not a full report")
    }
}

/**
 * The `resultId` of the `unchanged` report a pull with `previousResultId` answers, `None` for a full one.
 */
func unchangedId(snap: ServerSnapshot, previousResultId: String): ?String {
    let params = DocumentDiagnosticParams(textDocument: TextDocumentIdentifier(uri: URI),
        previousResultId: previousResultId)
    match (handleDocumentDiagnostic(snap, params)) {
        case DocumentDiagnosticReport.AsRelatedUnchangedDocumentDiagnosticReport(report) => report.resultId
        case _ => None<String>
    }
}

@Test
class DocumentDiagnosticTest {
    @TestCase
    func aSyntaxErrorIsReportedInTheColumnsAgreedOn() {
        // arrange - the emoji is two UTF-16 units and four bytes
        let state = opened("/* 😀 */ class A {")

        // act
        let items = pulled(state.snapshot())

        // assert
        @Expect(items.size, 1)
        @Expect(items[0].range.start.line, 0)
        @Expect(items[0].range.start.character, 18)
        @Expect(items[0].range.end.character, 18)
        @Expect(match (items[0].severity) {
            case Some(DiagnosticSeverity.Error) => true
            case _ => false
        })
        @Expect(items[0].source, "cjls")
    }

    @TestCase
    func inactiveCodeIsAHintTaggedUnnecessary() {
        // arrange - no project: `test` is not set
        let state = opened("@When[test] let a = 1")

        // act
        let items = pulled(state.snapshot())

        // assert
        @Expect(items.size, 1)
        @Expect(match (items[0].severity) {
            case Some(DiagnosticSeverity.Hint) => true
            case _ => false
        })
        @Expect(match (items[0].tags) {
            case Some(tags) => tags.size == 1 && match (tags[0]) {
                case DiagnosticTag.Unnecessary => true
                case _ => false
            }
            case None => false
        })
    }

    @TestCase
    func aDocumentTheServerDoesNotKnowHasNothingWrong() {
        // act
        let items = pulled(ServerState().snapshot())

        // assert
        @Expect(items.size, 0)
    }

    @TestCase
    func theSameDiagnosticsAgainAreUnchanged() {
        // arrange
        let state = opened("class A {")
        let first = fullReport(state.snapshot(), None<String>).resultId.getOrThrow()

        // act
        let id = unchangedId(state.snapshot(), first)

        // assert
        @Expect(id, Some(first))
    }

    @TestCase
    func anEditElsewhereThatKeepsTheDiagnosticsInPlaceLeavesThemUnchanged() {
        // arrange
        let state = opened("let a = 1\nclass A {")
        let first = fullReport(state.snapshot(), None<String>).resultId.getOrThrow()
        change(state, [partial("2", from: (0, 8), to: (0, 9))])

        // act
        let id = unchangedId(state.snapshot(), first)

        // assert
        @Expect(id, Some(first))
    }

    @TestCase
    func aDiagnosticMovedByAnEditIsReportedInFull() {
        // arrange - the same message, a line below
        let state = opened("class A {")
        let first = fullReport(state.snapshot(), None<String>).resultId.getOrThrow()
        change(state, [partial("\n", from: (0, 0), to: (0, 0))])

        // act
        let report = fullReport(state.snapshot(), first)

        // assert
        @Expect(report.items.size, 1)
        @Expect(report.items[0].range.start.line, 1)
        @Expect(report.resultId != Some(first))
    }

    @TestCase
    func anIdFromBeforeTheDocumentWasOpenedAgainIsAnsweredInFull() {
        // arrange - Neovim's `:e!` closes and opens the buffer, drops its diagnostics, keeps the id
        let state = opened("class A {")
        let first = fullReport(state.snapshot(), None<String>).resultId.getOrThrow()
        handleDidClose(state, DidCloseTextDocumentParams(textDocument: TextDocumentIdentifier(uri: URI)))
        handleDidOpen(Loop(state), Client(), NoopLogger(), DidOpenTextDocumentParams(
            textDocument: TextDocumentItem(uri: URI, languageId: LanguageKind("cangjie"), version: 3, text: "class A {")))

        // act
        let report = fullReport(state.snapshot(), first)

        // assert
        @Expect(report.items.size, 1)
    }
}
