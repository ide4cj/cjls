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

// this repository's `ginkgo` and `cjsyntax`, of std's `core` and `collection`: what `nodes.cj`, its largest
// file, is highlighted in
let highlightFixture: Fixture = {
    =>
    let text = StringBuilder()
    fixtureFiles(text, "ginkgo", "", Path("modules/ginkgo/src"), "ginkgo")
    fixtureFiles(text, "cjsyntax", " deps=ginkgo", Path("modules/cjsyntax/src"), "cjsyntax")
    fixtureFiles(text, "cjsyntax", " deps=ginkgo", Path("modules/cjsyntax/src/ast"), "cjsyntax.ast")
    Fixture.parse(text.toString())
}()

let nodesFile: FileId = highlightFixture.file("/cjsyntax/cjsyntax.ast/nodes.cj").fileId

// highlighted once: every body of the file inferred
let highlightDb: AnalysisDatabase = {
    =>
    let db = highlightFixture.database(binaries: ["std.core", "std.collection"].map {
        name => stdCjoRead(name, stdCjo(name))
    })
    highlight(db, nodesFile)
    db
}()

@Test
class HighlightBench {
    /**
     * Every body inferred already: what classifying the names costs.
     */
    @Bench
    func aLargeFileItsBodiesInferred(): Int64 {
        highlight(highlightDb, nodesFile).size
    }

    /**
     * An edit inside a body first: the bodies inferred again that it changes, and the classifying.
     */
    @Bench
    func aLargeFileAfterAnEditInABody(): Int64 {
        let text = highlightDb.sourceFile(nodesFile).getOrThrow().text(highlightDb).toString()
        highlightDb.setFileText(nodesFile, Rope(text))
        highlight(highlightDb, nodesFile).size
    }
}
