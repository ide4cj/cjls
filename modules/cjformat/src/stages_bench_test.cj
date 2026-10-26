package cjformat

import std.unittest.*
import std.unittest.testmacro.*
import std.env.getVariable
import cjsyntax.{CjParse, CjSyntaxNode, parse}

/**
 * Keep inputs and intermediate results alive outside the timed region. Stage measurements
 * isolate work, but their medians need not sum to the full call: allocation and GC differ.
 */
class FormatStageInput {
    let parsed: CjParse
    let root: CjSyntaxNode
    let doc: Doc
    let printed: String
    let edits: Array<TextEdit>

    FormatStageInput(let source: String) {
        parsed = parse(source)
        if (!parsed.errors.isEmpty()) {
            throw IllegalStateException("a formatter benchmark input must parse")
        }
        root = parsed.syntaxNode()
        doc = LayoutBuilder(source).node(root)
        printed = Printer(lineBreakIn(source), width: LINE_WIDTH).print(doc)
        edits = replacement(source, root.textRange, printed)
        if (applyEdits(source, edits) != printed) {
            throw IllegalStateException("benchmark edits must reproduce the printed document")
        }
    }
}

/**
 * Select one size per process when profiling: retaining every large document can distort
 * small-file GC costs. The default still runs the complete scaling series.
 */
func formatStageSizes(): Array<Int64> {
    match (getVariable("CJFORMAT_BENCH_STATEMENTS")) {
        case None => [100, 1000, 10000]
        case Some("100") => [100]
        case Some("1000") => [1000]
        case Some("10000") => [10000]
        case _ =>
            throw IllegalArgumentException("CJFORMAT_BENCH_STATEMENTS must be 100, 1000 or 10000")
    }
}

let FORMAT_STAGE_INPUTS =
    formatStageSizes()
        .map {
            n =>
            FormatStageInput(
                "func f() {\n${"call(firstArgument, secondArgument, thirdArgument)\n" * n}}\n"
            )
        }

/**
 * The same statement counts as FormatBench, with parsing and each formatter stage separated.
 * These synthetic files measure scaling; they do not represent every syntax or an LSP request.
 */
@Test
@Configure[warmup: Duration.second, minDuration: Duration.second]
class FormatStagesBench {
    @Bench[input in FORMAT_STAGE_INPUTS]
    func parseSource(input: FormatStageInput): CjParse {
        parse(input.source)
    }

    @Bench[input in FORMAT_STAGE_INPUTS]
    func materializeSource(input: FormatStageInput): String {
        input.root.text()
    }

    @Bench[input in FORMAT_STAGE_INPUTS]
    func buildLayout(input: FormatStageInput): Doc {
        LayoutBuilder(input.source).node(input.root)
    }

    @Bench[input in FORMAT_STAGE_INPUTS]
    func printLayout(input: FormatStageInput): String {
        Printer(lineBreakIn(input.source), width: LINE_WIDTH).print(input.doc)
    }

    @Bench[input in FORMAT_STAGE_INPUTS]
    func makeReplacement(input: FormatStageInput): Array<TextEdit> {
        replacement(input.source, input.root.textRange, input.printed)
    }

    @Bench[input in FORMAT_STAGE_INPUTS]
    func applyReplacement(input: FormatStageInput): String {
        applyEdits(input.source, input.edits)
    }

    @Bench[input in FORMAT_STAGE_INPUTS]
    func formatParsed(input: FormatStageInput): ?Array<TextEdit> {
        format(input.parsed)
    }

    @Bench[input in FORMAT_STAGE_INPUTS]
    func formatSource(input: FormatStageInput): ?String {
        formatText(input.source)
    }
}
