package cjls.handlers

import std.unittest.*
import std.unittest.testmacro.*
import rope.{Encoding, Rope}
import loupe.{Severity, TextRange}
import loupe.Diagnostic as LoupeDiagnostic
import cjls.lsp_types.*

@Test
class DiagnosticConversionTest {
    @TestCase[row in [(Severity.Error, DiagnosticSeverity.Error), (Severity.Warning, DiagnosticSeverity.Warning),
        (Severity.Hint, DiagnosticSeverity.Hint)]]
    func anEmptyMessageHasAFallbackWhateverItsSourceOrSeverity(row: (Severity, DiagnosticSeverity)) {
        // arrange
        let (severity, expectedSeverity) = row
        let input = LoupeDiagnostic(TextRange(1, 4), severity, "", unnecessary: true)

        // act
        let result = diagnostic(Rope("hello"), input, Encoding.Utf16)

        // assert
        @Expect(match (result.message) {
            case StringOrMarkupContent.AsString(message) => message
            case _ => ""
        }, "diagnostic reported without a message")
        @Expect(result.range.start.character, 1)
        @Expect(result.range.end.character, 4)
        @Expect(result.severity, Some(expectedSeverity))
        @Expect(result.source, Some("cjls"))
        @Expect(result.tags.getOrThrow(), [DiagnosticTag.Unnecessary])
    }

    @TestCase[text in ["the reported error", " ", "\n"]]
    func aNonemptyMessageIsPreservedVerbatim(text: String) {
        // act
        let result = diagnostic(Rope("hello"), LoupeDiagnostic(TextRange(0, 5), Severity.Error, text), Encoding.Utf16)

        // assert
        @Expect(match (result.message) {
            case StringOrMarkupContent.AsString(message) => message
            case _ => ""
        }, text)
    }
}
