package project_model

import std.collection.*
import std.env.{getVariable, getWorkingDirectory}
import std.fs.*
import std.runtime.{gc, getUsedHeapSize}
import std.unittest.*
import std.unittest.testmacro.*
import ginkgo.SyntaxElement
import cjsyntax.SyntaxKind
import cjsyntax.ast.identText
import rope.Rope
import loupe.db.{AnalysisDatabase, Package, SourceFile}
import loupe.hir.*
import loupe.syntax.parse
import index_map.IndexMap
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
     * Every identifier of every file looked up as a value, through the imports `levelOf` gives:
     * how many mean something.
     */
    func lookUpAll(levelOf: (Package, SourceFile) -> ImportLevel): Int64 {
        var found = 0
        for ((pkg, file, names) in files) {
            let defs = defMap(db, PackageRef.Source(pkg))
            let imports = levelOf(pkg, file)
            for (name in names) {
                if (lookUpIn(db, defs, ItemFile.Source(file), imports, name, Namespace.Values) != Resolution.NotFound) {
                    found++
                }
            }
        }
        found
    }

    /**
     * What both levels read: every file's item tree, every package's def map and exports.
     */
    func readShared(): Unit {
        for ((_, file, _) in files) {
            itemTree(db, file)
        }
        for ((_, packages) in packageIndex(db).packages) {
            for (indexed in packages) {
                defMap(db, indexed.pkg)
                packageExports(db, indexed.pkg)
            }
        }
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

func lazyLevel(db: AnalysisDatabase): (Package, SourceFile) -> ImportLevel {
    {pkg: Package, file: SourceFile => importsOf(db, pkg, file)}
}

func mergedLevel(db: AnalysisDatabase): (Package, SourceFile) -> ImportLevel {
    {pkg: Package, file: SourceFile => mergedImports(db, pkg, file)}
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
 * A file's scope, its imports kept with their globs (`importsOf`, A) or read whole
 * (`mergedImports`, B), on this repository: `cjpm bench '--filter=ScopeBench.*'`.
 */
@Test
class ScopeBench {
    @Bench
    func lookUpEveryIdentifierLazy(): Int64 {
        let ws = workspace()
        ws.lookUpAll(lazyLevel(ws.db))
    }

    @Bench
    func lookUpEveryIdentifierMerged(): Int64 {
        let ws = workspace()
        ws.lookUpAll(mergedLevel(ws.db))
    }

    @Bench
    func addANameToTheMostGlobbedPackageThenLookUpLazy(): Int64 {
        let ws = workspace()
        toggle(ws)
        ws.lookUpAll(lazyLevel(ws.db))
    }

    @Bench
    func addANameToTheMostGlobbedPackageThenLookUpMerged(): Int64 {
        let ws = workspace()
        toggle(ws)
        ws.lookUpAll(mergedLevel(ws.db))
    }
}

var memoryPrinted = false

/**
 * The heap a level of imports holds for every file of this repository, each on a database of its
 * own: `cjpm bench '--filter=ScopeMemoryBench.*'`, printed once.
 */
@Test
class ScopeMemoryBench {
    @Bench
    func heldByEveryFilesImports(): Int64 {
        if (memoryPrinted) {
            return 0
        }
        memoryPrinted = true
        let ws = BenchWorkspace()
        ws.readShared()
        ws.lookUpAll(lazyLevel(ws.db))
        ws.lookUpAll(mergedLevel(ws.db))
        let identifiers = ws.files.iterator().fold(0) {sum, it => sum + it[2].size}
        println("${ws.files.size} files, ${identifiers} identifiers")
        let packages = HashSet<Package>()
        for ((pkg, _, _) in ws.files) {
            packages.add(pkg)
        }
        // A: each file's imports and each package's re-exports, globs kept as their packages
        let lazyNames = ws.files.iterator().fold(0) {sum, it => sum + fileImports(ws.db, it[0], it[1]).names.size}
        let lazyBytes = heldBy {
            =>
            let held = ArrayList<ImportedNames>()
            for ((pkg, file, _) in ws.files) {
                held.add(copyOf(fileImports(ws.db, pkg, file)))
            }
            for (pkg in packages) {
                held.add(copyOf(packageImports(ws.db, PackageRef.Source(pkg))))
            }
            held
        }
        println("lazy: ${lazyNames} names held, ${lazyBytes / 1024} KiB")
        // B: each file's imports with every glob read whole
        let mergedNames = ws.files.iterator().fold(0) {sum, it => sum + mergedImports(ws.db, it[0], it[1]).size}
        let mergedBytes = heldBy {
            =>
            let held = ArrayList<MergedImports>()
            for ((pkg, file, _) in ws.files) {
                let merged = mergedImports(ws.db, pkg, file)
                held.add(MergedImports(copyOf(merged.byName), copyOf(merged.ctorsByName)))
            }
            held
        }
        println("merged: ${mergedNames} names held, ${mergedBytes / 1024} KiB")
        0
    }
}

const COPIES = 10

/**
 * The heap what `make` makes holds: `COPIES` of it held at once, the growth of the heap shared out.
 */
func heldBy<T>(make: () -> T): Int64 {
    let before = settledHeap()
    let copies = ArrayList<T>()
    for (_ in 0..COPIES) {
        copies.add(make())
    }
    let after = settledHeap()
    // keeps them alive past the reading
    if (copies.size != COPIES) {
        throw IllegalStateException("copies lost")
    }
    (after - before) / COPIES
}

func copyOf<V>(map: IndexMap<String, Array<V>>): IndexMap<String, Array<V>> {
    IndexMap<String, Array<V>>(map.toArray().map {entry => (entry[0], entry[1].clone())})
}

func copyOf(names: ImportedNames): ImportedNames {
    ImportedNames(copyOf(names.names), copyOf(names.ctors), names.globs.clone())
}

/**
 * The heap in use once the garbage is collected: collected until two readings in a row are
 * within a MiB of each other.
 */
func settledHeap(): Int64 {
    var last = Int64.Max
    for (_ in 0..50) {
        gc(heavy: true)
        sleep(Duration.millisecond * 100)
        let now = getUsedHeapSize()
        if (now - last < 1024 * 1024 && last - now < 1024 * 1024) {
            return now
        }
        last = now
    }
    throw IllegalStateException("the heap does not settle")
}
