package loupe

import std.collection.*
import std.deriving.*
import std.sort.*
import ginkgo.TextRange
import cjsyntax.message
import loupe.vfs.FileId
import loupe.db.AnalysisDatabase
import loupe.hir.whenDiagnostics
import loupe.syntax.parse

@Derive[Equatable]
public enum Severity {
    | Error
    // not a fault: what a reader may want to know, as code a `@When` leaves out
    | Hint
}

/**
 * Something wrong in a file, or worth knowing of it. `range` is where its source put it, empty ones
 * included, as "expected `}`" at the end of a file (A12). `unnecessary` for code a build leaves
 * out, which an editor shows faded.
 */
@Derive[Equatable]
public struct Diagnostic {
    public Diagnostic(public let range: TextRange, public let severity: Severity, public let message: String,
        public let unnecessary!: Bool = false) {}
}

/**
 * What is wrong in a file, in the order of the text: what the lexer and the parser found, and what
 * its `@When`s say: the code they leave out, and what cjc rejects in them. Empty for a file the
 * database does not know.
 *
 * Not a query: every source of diagnostics is one (`parse`, `whenDiagnostics`, later validation and
 * name resolution), remembered there, and this only collects their results (A11).
 */
public func diagnostics(db: AnalysisDatabase, fileId: FileId): Array<Diagnostic> {
    let file = db.sourceFile(fileId) ?? return []
    let result = ArrayList<Diagnostic>()
    result.add(all: parse(db, file).errors.map {error => Diagnostic(error.range, Severity.Error, message(error.error))})
    let conditional = whenDiagnostics(db, file)
    result.add(all: conditional.errors.map {error => Diagnostic(error.range, Severity.Error, error.message)})
    result.add(all: conditional.inactive.map {
        code => Diagnostic(code.range, Severity.Hint,
            "code is inactive due to @When: ${String.join(code.reasons, delimiter: " and ")}", unnecessary: true)
    })
    let sorted = result.toArray()
    sort(sorted, stable: true, by: {a: Diagnostic, b: Diagnostic => a.range.start.compare(b.range.start)})
    sorted
}
