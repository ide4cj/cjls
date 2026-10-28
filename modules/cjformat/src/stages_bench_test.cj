package cjformat

import std.env.getVariable
import std.unittest.*
import std.unittest.testmacro.*
import cjsyntax.{CjParse, CjSyntaxNode, parse}
import ginkgo.TextRange

// Match formatter_cli.py explicitly so default policy changes cannot skew stage comparisons.
let FORMAT_STAGE_OPTIONS =
    FormatOptions(lineWidth: 100, indentWidth: 4, simpleIf: SimpleIf.Multiline)

/**
 * A layout measurement needs the source tree, but must not retain a previously built document.
 */
class FormatParsedInput {
    let parsed: CjParse
    let root: CjSyntaxNode

    FormatParsedInput(let source: String) {
        parsed = parse(source)
        if (!parsed.errors.isEmpty()) {
            throw IllegalStateException("a formatter benchmark input must parse")
        }
        root = parsed.syntaxNode()
    }
}

/**
 * Printing retains its document, not the temporary source tree used to construct it.
 */
class FormatPrintInput {
    let doc: Doc
    let newline: String

    FormatPrintInput(input: FormatParsedInput) {
        doc = LayoutBuilder(input.source, options: FORMAT_STAGE_OPTIONS).node(input.root)
        newline = lineBreakIn(input.source)
    }
}

/**
 * Edit measurements retain text and edits, without pinning a document during unrelated stages.
 */
class FormatEditInput {
    let printed: String
    let edits: Array<TextEdit>

    FormatEditInput(let source: String) {
        printed =
            formatText(source, options: FORMAT_STAGE_OPTIONS) ??
                throw IllegalStateException("a benchmark input must format")
        edits = replacement(source, TextRange(0, source.size), printed)
        if (applyEdits(source, edits) != printed) {
            throw IllegalStateException("benchmark edits must reproduce the printed document")
        }
    }
}

/**
 * A single size per process avoids retaining large fixtures during small-file measurements.
 */
func formatStageSize(): Int64 {
    match (getVariable("CJFORMAT_BENCH_STATEMENTS")) {
        case None | Some("1000") => 1000
        case Some("100") => 100
        case Some("10000") => 10000
        case _ =>
            throw IllegalArgumentException("CJFORMAT_BENCH_STATEMENTS must be 100, 1000 or 10000")
    }
}

/**
 * Data providers run outside the timed body, and keep only the selected stage's inputs alive.
 */
func formatStageSources(): Array<String> {
    let n = formatStageSize()
    ["func f() {\n${"call(firstArgument, secondArgument, thirdArgument)\n" * n}}\n"]
}

/**
 * Pre-parsed inputs isolate source reconstruction, layout and formatting from parser costs.
 */
func formatStageParsedInputs(): Array<FormatParsedInput> {
    formatStageSources().map { source => FormatParsedInput(source) }
}

/**
 * Pre-built documents isolate printing from layout construction.
 */
func formatStagePrintInputs(): Array<FormatPrintInput> {
    formatStageParsedInputs().map { input => FormatPrintInput(input) }
}

/**
 * Pre-formatted outputs isolate replacement calculation and application.
 */
func formatStageEditInputs(): Array<FormatEditInput> {
    formatStageSources().map { source => FormatEditInput(source) }
}

/**
 * Synthetic scaling inputs, not an LSP request or a representative syntax corpus. Stage
 * medians need not sum to the full call: allocation and GC differ between isolated operations.
 */
@Test
@Configure[warmup: Duration.second, minDuration: Duration.second]
class FormatStagesBench {
    @Bench[source in formatStageSources()]
    func parseSource(source: String): CjParse {
        parse(source)
    }

    @Bench[input in formatStageParsedInputs()]
    func materializeSource(input: FormatParsedInput): String {
        input.root.text()
    }

    @Bench[input in formatStageParsedInputs()]
    func buildLayout(input: FormatParsedInput): Doc {
        LayoutBuilder(input.source, options: FORMAT_STAGE_OPTIONS).node(input.root)
    }

    @Bench[input in formatStagePrintInputs()]
    func printLayout(input: FormatPrintInput): String {
        Printer(
            input.newline,
            width: FORMAT_STAGE_OPTIONS.lineWidth,
            indentWidth: FORMAT_STAGE_OPTIONS.indentWidth
        )
            .print(input.doc)
    }

    @Bench[input in formatStageEditInputs()]
    func makeReplacement(input: FormatEditInput): Array<TextEdit> {
        replacement(input.source, TextRange(0, input.source.size), input.printed)
    }

    @Bench[input in formatStageEditInputs()]
    func applyReplacement(input: FormatEditInput): String {
        applyEdits(input.source, input.edits)
    }

    @Bench[input in formatStageParsedInputs()]
    func formatParsed(input: FormatParsedInput): ?Array<TextEdit> {
        format(input.parsed, options: FORMAT_STAGE_OPTIONS)
    }

    @Bench[source in formatStageSources()]
    func formatSource(source: String): ?String {
        formatText(source, options: FORMAT_STAGE_OPTIONS)
    }
}
