package project_model

import std.collection.*
import std.env.getVariable
import std.fs.*
import std.sort.sort
import std.unittest.*
import std.unittest.testmacro.*
import loupe.diagnostics
import loupe.db.{AnalysisDatabase, BinaryModel, BinaryPackage, ModuleModel, PackageModel, ProjectModel}
import loupe.fixture.{stdSourcesDir, UPDATE_EXPECT}
import loupe.vfs.{isCangjieFile, PathInterner, readCjoFiles, readFiles, Vfs, VfsPath}

/**
 * Each diagnostic of the files of `db` among `files`, as `path:line: message`, the path relative to
 * `root` with `/`s; sorted.
 */
func diagnosticsOf(db: AnalysisDatabase, paths: PathInterner, files: Array<VfsPath>, root: VfsPath): Array<String> {
    let found = ArrayList<String>()
    let prefix = root.toString().replace("\\", "/") + "/"
    for (path in files) {
        let fileId = paths.lookup(path) ?? continue
        let file = db.sourceFile(fileId) ?? continue
        let text = file.text(db).toString()
        let name = path.toString().replace("\\", "/").removePrefix(prefix)
        for (one in diagnostics(db, fileId)) {
            let line = text[..one.range.start].count("\n") + 1
            found.add("${name}:${line}: ${one.message}")
        }
    }
    let sorted = found.toArray()
    sort(sorted)
    sorted
}

/**
 * The package `file` declares, by its first line of `package`, after its modifiers.
 */
func declaredPackageOf(file: Path): ?String {
    for (line in String.fromUtf8(File.readFrom(file)).split("\n")) {
        // `macro package`, `protected package`, …
        let words = line.trimAscii().split(" ", removeEmpty: true)
        for (i in 0..words.size where words[i] == "package" && i + 1 < words.size) {
            return words[i + 1]
        }
    }
    None
}

/**
 * std's sources, `.corpora/`'s at the nightly's commit (D65), a module of their own: each package of
 * them but `std.core`, read from the SDK's `.cjo` while the compiler's own types are not types of
 * the analysis's (#218).
 */
func stdFromSources(): (AnalysisDatabase, PathInterner, Array<VfsPath>) {
    let dir = stdSourcesDir()
    let byPackage = HashMap<String, ArrayList<VfsPath>>()
    func walk(at: Path): Unit {
        for (info in Directory.readFrom(at)) {
            if (info.isDirectory()) {
                walk(info.path)
            } else if (info.isRegular() && isCangjieFile(info.name)) {
                let name = declaredPackageOf(info.path) ?? continue
                let files = byPackage.get(name) ?? ArrayList<VfsPath>()
                files.add(VfsPath.file(info.path))
                byPackage[name] = files
            }
        }
    }
    walk(dir.filePath.getOrThrow())
    let packages = byPackage.keys().toArray().filter {name => name != "std.core"}.map {
        name =>
        let files = byPackage[name].toArray()
        PackageModel(name, files[0].parent.getOrThrow(), files)
    }
    let home = getVariable("CANGJIE_HOME") ?? throw IllegalStateException("CANGJIE_HOME names no SDK")
    let target = Directory.readFrom(Path(home).join("modules")).filter {info => info.isDirectory()}[0].name
    let core = VfsPath.file(Path(home).join("modules").join(target).join("std").join("std.core.cjo"))
    let model = ProjectModel(findProject(workspaceRoot(), env: {name => getVariable(name)}).model.cfg,
        [ModuleModel("std", dir, packages)], binaries: [BinaryModel("std", [], packages: [BinaryPackage("std.core", core)])])
    let db = AnalysisDatabase()
    let vfs = Vfs()
    db.setProject(model, vfs.paths, binaries: readCjoFiles(model.cjoFiles()).files)
    for ((path, text) in readFiles(model.files()).files) {
        vfs.setFileContents(path, text)
    }
    db.applyChanges(vfs, vfs.takeChanges())
    (db, vfs.paths, model.files())
}

/**
 * The file of what the gate finds on std's sources and why, a line `path:line: message  # why` each:
 * a gap of the analysis, its issue named, or of the corpus; none of std.
 */
func knownOfStd(): Path {
    workspaceRoot().filePath.getOrThrow().join("modules").join("project_model").join("std_diagnostics_known.txt")
}

/**
 * No diagnostic on a source cjc compiles with none (#48's 8c′b gate): a false error of the analysis
 * fails it, named. A cold pass over every body of each.
 */
@Test
@Timeout[Duration.minute * 5]
class DiagnosticsGateTest {
    @TestCase
    func thisRepositoryHasNoDiagnostic() {
        let ws = workspace()
        let files = ws.files.toArray().map {one => ws.paths.path(one[1].fileId(ws.db))}
        @Expect(diagnosticsOf(ws.db, ws.paths, files, workspaceRoot()), Array<String>())
    }

    /**
     * std's sources have the diagnostics `std_diagnostics_known.txt` lists, no more and no fewer: a
     * new one is a false error, one gone a gap closed, to take off the list, which only shrinks.
     * `UPDATE_EXPECT=1` writes it, keeping the why of each line still found; a new one's `?` is to be
     * written.
     */
    @TestCase
    func stdsSourcesHaveOnlyTheDiagnosticsOfKnownGaps() {
        let (db, paths, files) = stdFromSources()
        let found = diagnosticsOf(db, paths, files, stdSourcesDir())
        let lines = String.fromUtf8(File.readFrom(knownOfStd())).replace("\r\n", "\n").split("\n")
        let header = lines.filter {line => line.startsWith("#")}
        let why = HashMap<String, String>()
        for (line in lines where !line.startsWith("#") && !line.isEmpty()) {
            let parts = line.split("  # ", 2)
            why[parts[0]] = parts.get(1) ?? "?"
        }
        if (getVariable(UPDATE_EXPECT).isSome()) {
            let written = found.map {one => "${one}  # ${why.get(one) ?? "?"}"}
            File.writeTo(knownOfStd(), (String.join(header.concat(written), delimiter: "\n") + "\n").toArray())
            return
        }
        let known = why.keys().toArray()
        sort(known)
        @Expect(found, known)
    }
}
