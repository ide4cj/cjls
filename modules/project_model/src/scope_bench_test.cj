package project_model

import std.collection.*
import std.env.{getVariable, getWorkingDirectory}
import std.fs.*
import std.unittest.*
import std.unittest.testmacro.*
import ginkgo.SyntaxElement
import cjsyntax.SyntaxKind
import cjsyntax.ast.identText
import rope.Rope
import loupe.db.{AnalysisDatabase, Package, SourceFile}
import loupe.hir.*
import loupe.syntax.parse
import loupe.vfs.{FileId, readCjoFiles, readFiles, Vfs, VfsPath}

/**
 * The workspace this repository is, loaded as the server loads one: its project, the `.cjo` of
 * `std` and stdx, the texts of its files.
 */
class BenchWorkspace {
    let db = AnalysisDatabase()
    /**
     * Each file of the user's modules, its package, and the identifiers it uses, each once.
     */
    let files = ArrayList<(Package, SourceFile, Array<String>)>()

    init() {
        let root = workspaceRoot()
        let load = findProject(root, env: {name => getVariable(name)})
        let vfs = Vfs()
        let binaries = readCjoFiles(load.model.cjoFiles())
        db.setProject(load.model, vfs.paths, binaries: binaries.files)
        for ((path, text) in readFiles(load.model.files()).files) {
            vfs.setFileContents(path, text)
        }
        db.applyChanges(vfs, vfs.takeChanges())
        for (module in db.project().getOrThrow().modules(db) where module.member(db)) {
            for (pkg in module.packages(db)) {
                for (fileId in pkg.files(db)) {
                    if (let Some(file) <- db.sourceFile(fileId)) {
                        files.add((pkg, file, identifiersOf(file)))
                    }
                }
            }
        }
    }

    private func identifiersOf(file: SourceFile): Array<String> {
        let seen = HashSet<String>()
        let names = ArrayList<String>()
        for (element in parse(db, file).syntaxNode().descendantsWithTokens()) {
            if (let SyntaxElement.Token(token) <- element && token.kind == SyntaxKind.Ident) {
                let name = identText(token)
                if (seen.add(name)) {
                    names.add(name)
                }
            }
        }
        names.toArray()
    }

    /**
     * Every identifier of every file looked up as a value: how many mean something.
     */
    func lookUpAll(): Int64 {
        var found = 0
        for ((pkg, file, names) in files) {
            let defs = defMap(db, PackageRef.Source(pkg))
            let imports = importsOf(db, pkg, file)
            let ctorImports = ctorImportsOf(db, pkg)
            for (name in names) {
                if (lookUpIn(db, defs, ItemFile.Source(file), imports, name, Namespace.Values, ctorImports: ctorImports) != Resolution.NotFound) {
                    found++
                }
            }
        }
        found
    }

    /**
     * The source package the most files import by a glob, and its first file.
     */
    func mostGlobbed(): (Package, FileId) {
        let counts = HashMap<Package, Int64>()
        for ((pkg, file, _) in files) {
            for (glob in fileImports(db, pkg, file).globs) {
                if (let Source(target) <- glob.pkg) {
                    counts[target] = (counts.get(target) ?? 0) + 1
                }
            }
        }
        var best: ?(Package, Int64) = None
        for ((pkg, count) in counts) {
            if (best.map {it => it[1] < count} ?? true) {
                best = (pkg, count)
            }
        }
        let pkg = best.getOrThrow()[0]
        (pkg, pkg.files(db)[0])
    }
}

/**
 * The directory of the workspace's `cjpm.toml`, from the working directory up.
 */
func workspaceRoot(): VfsPath {
    var dir = VfsPath.file(getWorkingDirectory())
    while (true) {
        let manifest = dir.join("cjpm.toml").filePath.getOrThrow()
        if (exists(manifest) && String.fromUtf8(File.readFrom(manifest)).contains("[workspace]")) {
            return dir
        }
        dir = dir.parent ?? throw IllegalStateException("no workspace above ${getWorkingDirectory()}")
    }
    throw IllegalStateException("unreachable")
}

/**
 * The workspace of the benches, loaded by the first.
 */
var benchWorkspace: ?BenchWorkspace = None

func workspace(): BenchWorkspace {
    if (let Some(loaded) <- benchWorkspace) {
        return loaded
    }
    let loaded = BenchWorkspace()
    benchWorkspace = loaded
    loaded
}

/**
 * A text for the most globbed package's first file, a name added to it or not, by turns.
 */
var toggled = false

func toggle(ws: BenchWorkspace): Unit {
    let (_, fileId) = ws.mostGlobbed()
    let file = ws.db.sourceFile(fileId).getOrThrow()
    let text = file.text(ws.db).toString()
    let added = "\npublic func scopeBenchAdded() {}\n"
    let next = if (toggled) {
        text.replace(added, "")
    } else {
        text + added
    }
    toggled = !toggled
    ws.db.setFileText(fileId, Rope(next))
}

/**
 * A file's scope on this repository, its identifiers looked up: `cjpm bench '--filter=ScopeBench.*'`.
 */
@Test
class ScopeBench {
    @Bench
    func lookUpEveryIdentifier(): Int64 {
        workspace().lookUpAll()
    }

    /**
     * A declaration added to the package the most files import by a glob, or taken away: the
     * imports of those files stay as they were, what they bring is read again (D47).
     */
    @Bench
    func addANameToTheMostGlobbedPackageThenLookUpEveryIdentifier(): Int64 {
        let ws = workspace()
        toggle(ws)
        ws.lookUpAll()
    }
}
