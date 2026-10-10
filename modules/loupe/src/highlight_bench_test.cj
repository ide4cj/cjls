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
     * An edit inside a body first: the bodies inferred again that it changes, and the classifying.
     */
    @Bench
    func aLargeFileAfterAnEditInABody(): Int64 {
        let state = highlightBench()
        let text = state.db.sourceFile(state.nodesFile).getOrThrow().text(state.db).toString()
        state.db.setFileText(state.nodesFile, Rope(text))
        highlight(state.db, state.nodesFile).size
    }
}
