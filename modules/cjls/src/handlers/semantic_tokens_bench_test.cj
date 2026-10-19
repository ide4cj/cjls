package cjls.handlers

import std.collection.*
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import stdxx.{IntegerOrString, Nullable}
import fjson.*
import jsonrpc.*
import rope.{Encoding, Rope}
import loupe.*
import loupe.db.AnalysisDatabase
import loupe.fixture.*
import loupe.vfs.FileId
import cjls.lsp_types.*

/*
 * What `textDocument/semanticTokens/full` costs a keystroke in a large file, piece by piece, against
 * what `full/delta` would add and save (#56): `cjsyntax`'s `nodes.cj`, its 6.6 thousand lines, every
 * body inferred, as `loupe`'s `HighlightBench` has it.
 *
 * `cjHeapSize=4GB cjpm bench '--filter=SemanticTokensBench.*'`
 */

/**
 * The sources of `dir` but the tests, under `/<module>/…`, of the package `pkg`, as fixture files.
 */
func tokensFixtureFiles(text: StringBuilder, module: String, deps: String, dir: Path, pkg: String): Unit {
    let files = Directory.readFrom(dir).filter {info => info.isRegular() && info.name.endsWith(".cj") &&
        !info.name.endsWith("_test.cj")}
    for (info in files) {
        text.append("//- /${module}/${pkg}/${info.name} module=${module} package=${pkg}${deps}\n")
        text.append(String.fromUtf8(File.readFrom(info.path)))
        text.append("\n")
    }
}

/**
 * The longest common prefix and suffix of `old` and `new` in whole tokens, the rest one edit: what
 * rust-analyzer sends.
 */
func tokensDelta(old: Array<UInt32>, new: Array<UInt32>): Array<SemanticTokensEdit> {
    var prefix = 0
    while (prefix < old.size && prefix < new.size && old[prefix] == new[prefix]) {
        prefix++
    }
    prefix -= prefix % 5
    var suffix = 0
    while (suffix < old.size - prefix && suffix < new.size - prefix &&
        old[old.size - 1 - suffix] == new[new.size - 1 - suffix]) {
        suffix++
    }
    suffix -= suffix % 5
    if (prefix == old.size && prefix == new.size) {
        return []
    }
    [SemanticTokensEdit(start: UInt32(prefix), deleteCount: UInt32(old.size - prefix - suffix),
        data: new[prefix..new.size - suffix])]
}

func tokensResponse(result: RawJson): Array<Byte> {
    toJsonBytes(ResponseBody(Nullable.Value(IntegerOrString.Integer(7)), ResultOrError.Result(result)).enveloped())
}

class SemanticTokensBenchState {
    let db: AnalysisDatabase
    let nodesFile: FileId
    // the text of the file, and the same with a space more inside the body of its last method, set in turn
    let texts: Array<String>
    var edits = 0
    // what the handler has after `highlight`, and the tokens of the two texts, as the client gets them
    let highlighted: Array<HighlightedRange>
    let rope: Rope
    let before: SemanticTokens
    let after: SemanticTokens

    init() {
        let text = StringBuilder()
        tokensFixtureFiles(text, "ginkgo", "", Path("modules/ginkgo/src"), "ginkgo")
        tokensFixtureFiles(text, "cjsyntax", " deps=ginkgo", Path("modules/cjsyntax/src"), "cjsyntax")
        tokensFixtureFiles(text, "cjsyntax", " deps=ginkgo", Path("modules/cjsyntax/src/ast"), "cjsyntax.ast")
        let fixture = Fixture.parse(text.toString())
        nodesFile = fixture.file("/cjsyntax/cjsyntax.ast/nodes.cj").fileId
        db = fixture.database(binaries: ["std.core", "std.collection"].map {
            name => stdCjoRead(name, stdCjo(name))
        })
        let source = db.sourceFile(nodesFile).getOrThrow().text(db).toString()
        let at = source.lastIndexOf("\n    }\n").getOrThrow()
        texts = [source, source[..at] + " " + source[at..]]
        rope = Rope(texts[0])
        highlighted = highlight(db, nodesFile)
        before = semanticTokens(rope, highlighted, Encoding.Utf16, false)
        db.setFileText(nodesFile, Rope(texts[1]))
        after = semanticTokens(Rope(texts[1]), highlight(db, nodesFile), Encoding.Utf16, false)
        db.setFileText(nodesFile, rope)
        highlight(db, nodesFile)
    }
}

var semanticTokensBenchState: ?SemanticTokensBenchState = None

func semanticTokensBench(): SemanticTokensBenchState {
    if (let Some(state) <- semanticTokensBenchState) {
        return state
    }
    let state = SemanticTokensBenchState()
    semanticTokensBenchState = state
    state
}

@Test
class SemanticTokensBench {
    /**
     * What every request pays and `full/delta` does not save: the edit's queries and the classifying.
     */
    @Bench
    func highlightAfterAnEdit(): Int64 {
        let state = semanticTokensBench()
        state.edits++
        state.db.setFileText(state.nodesFile, Rope(state.texts[state.edits % 2]))
        highlight(state.db, state.nodesFile).size
    }

    /**
     * Ranges to five numbers a token, positions in UTF-16: paid with or without a delta.
     */
    @Bench
    func encodeTokens(): Int64 {
        let state = semanticTokensBench()
        semanticTokens(state.rope, state.highlighted, Encoding.Utf16, false).data.size
    }

    /**
     * The whole answer to the wire, as `full` sends it now: what a delta saves.
     */
    @Bench
    func writeFullResponse(): Int64 {
        let state = semanticTokensBench()
        tokensResponse(SemanticTokensRequestSpec().encodeResult(Nullable.Value(state.after))).size
    }

    /**
     * What `full/delta` pays instead: the id, a hash of the tokens as D131's, the edit from the last
     * tokens, and that to the wire.
     */
    @Bench
    func hashDiffAndWriteDelta(): Int64 {
        let state = semanticTokensBench()
        var hasher = DefaultHasher()
        for (value in state.after.data) {
            hasher.write(value)
        }
        let resultId = "${hasher.finish()}"
        let delta = SemanticTokensDelta(resultId: resultId, edits: tokensDelta(state.before.data, state.after.data))
        tokensResponse(SemanticTokensDeltaRequestSpec().encodeResult(
            Nullable.Value(SemanticTokensOrSemanticTokensDelta.AsSemanticTokensDelta(delta)))).size
    }
}
