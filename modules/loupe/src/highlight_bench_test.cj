package loupe

import std.collection.*
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import rope.Rope
import loupe.db.AnalysisDatabase
import loupe.fixture.*
import loupe.vfs.FileId

/**
 * The sources of `dir` but the tests, under `/<module>/…`, of the package `pkg`, as fixture files.
 */
func fixtureFiles(text: StringBuilder, module: String, deps: String, dir: Path, pkg: String): Unit {
    let files = Directory.readFrom(dir).filter {info => info.isRegular() && info.name.endsWith(".cj") &&
        !info.name.endsWith("_test.cj")}
    for (info in files) {
        text.append("//- /${module}/${pkg}/${info.name} module=${module} package=${pkg}${deps}\n")
        text.append(String.fromUtf8(File.readFrom(info.path)))
        text.append("\n")
    }
}

/**
 * This repository's `ginkgo` and `cjsyntax`, of std's `core` and `collection`, `nodes.cj`, its largest file, highlighted
 * once: every body of the file inferred. Made by the first bench that asks, not when the package starts: `cjpm test`
 * runs no bench, and should not pay for it.
 */
class HighlightBenchState {
    let db: AnalysisDatabase
    let nodesFile: FileId
    // the text of the file, and the same with a space more inside the body of its last method: the bench sets them in
    // turn, so each run is an edit
    let texts: Array<String>
    var edits = 0

    init() {
        let text = StringBuilder()
        fixtureFiles(text, "ginkgo", "", Path("modules/ginkgo/src"), "ginkgo")
        fixtureFiles(text, "cjsyntax", " deps=ginkgo", Path("modules/cjsyntax/src"), "cjsyntax")
        fixtureFiles(text, "cjsyntax", " deps=ginkgo", Path("modules/cjsyntax/src/ast"), "cjsyntax.ast")
        let fixture = Fixture.parse(text.toString())
        nodesFile = fixture.file("/cjsyntax/cjsyntax.ast/nodes.cj").fileId
        db = fixture.database(binaries: ["std.core", "std.collection"].map {
            name => stdCjoRead(name, stdCjo(name))
        })
        let source = db.sourceFile(nodesFile).getOrThrow().text(db).toString()
        let at = source.lastIndexOf("\n    }\n").getOrThrow()
        texts = [source, source[..at] + " " + source[at..]]
        highlight(db, nodesFile)
    }
}

var highlightBenchState: ?HighlightBenchState = None

func highlightBench(): HighlightBenchState {
    if (let Some(state) <- highlightBenchState) {
        return state
    }
    let state = HighlightBenchState()
    highlightBenchState = state
    state
}

@Test
class HighlightBench {
    /**
     * Every body inferred already: what classifying the names costs.
     */
    @Bench
    func aLargeFileItsBodiesInferred(): Int64 {
        let state = highlightBench()
        highlight(state.db, state.nodesFile).size
    }

    /**
     * An edit inside the last body first: the file parsed again, every memo of the file verified, what the edit changes
     * computed again, and the classifying.
     */
    @Bench
    func aLargeFileAfterAnEditInABody(): Int64 {
        let state = highlightBench()
        state.edits++
        state.db.setFileText(state.nodesFile, Rope(state.texts[state.edits % 2]))
        highlight(state.db, state.nodesFile).size
    }
}
