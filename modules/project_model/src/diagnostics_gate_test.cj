package project_model

import std.collection.{ArrayList, HashMap}
import std.env.getVariable
import std.fs.{Directory, File, Path}
import std.sort.sort
import std.unittest.*
import std.unittest.testmacro.*
import loupe.{diagnostics, Severity}
import loupe.db.{AnalysisDatabase, Cfg, ModuleModel, PackageModel, ProjectModel}
import loupe.fixture.{stdSourcesDir, UPDATE_EXPECT}
import loupe.hir.{bodyWithSourceMap, macroCallHeadOf, sourceRangeOf}
import loupe.syntax.parse
import loupe.vfs.{isCangjieFile, PathInterner, readFiles, Vfs, VfsPath}

/**
 * Each diagnostic of the files of `db` among `files`, as `path:line: message`, the path relative to
 * `root` with `/`s; sorted.
 */
func diagnosticsOf(
    db: AnalysisDatabase,
    paths: PathInterner,
    files: Array<VfsPath>,
    root: VfsPath
): Array<String> {
    let found = ArrayList<String>()
    for (path in files) {
        let fileId = paths.lookup(path) ?? continue
        let file = db.sourceFile(fileId) ?? continue
        let text = file.text(db).toString()
        let name = relativeName(path, root)
        for (one in diagnostics(db, fileId) where one.severity != Severity.Hint) {
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
 * What std's sources are analyzed under by the gate on every host, as `std_diagnostics_known.txt` is
 * written: Linux on x86_64. `@When` picks which of std's twins are read.
 */
let STD_GATE_CFG =
    Cfg(
        [
            ("os", "Linux"),
            ("arch", "x86_64"),
            ("env", "gnu"),
            ("backend", "cjnative"),
            ("test", "true")
        ]
    )

/**
 * Loads the pinned std sources, including std.core, under the gate's fixed target configuration.
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
    let packages =
        byPackage
            .keys()
            .toArray()
            .map {
                name =>
                let files = byPackage[name].toArray()
                PackageModel(name, files[0].parent.getOrThrow(), files)
            }
    let model = ProjectModel(STD_GATE_CFG, [ModuleModel("std", dir, packages)])
    let db = AnalysisDatabase()
    let vfs = Vfs()
    db.setProject(model, vfs.paths)
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
    workspaceRoot()
        .filePath
        .getOrThrow()
        .join("modules")
        .join("project_model")
        .join("std_diagnostics_known.txt")
}

/**
 * No diagnostic on a source cjc compiles with none (#48's 8c′b gate): a false error of the analysis
 * fails it, named. A cold pass over every body of each. Tagged `gate`, as `ErrorRootsGateTest` is: the
 * coverage run leaves them out (D120).
 */
@Test
@Tag[gate]
@Timeout[Duration.minute * 5]
class DiagnosticsGateTest {
    @TestCase
    func thisRepositoryHasNoDiagnostic() {
        let ws = workspace()
        let files = ws.files.toArray().map { one => ws.paths.path(one[1].fileId(ws.db)) }
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
        let header = lines.filter { line => line.startsWith("#") }
        let why = HashMap<String, String>()
        for (line in lines where !line.startsWith("#") && !line.isEmpty()) {
            let parts = line.split("  # ", 2)
            why[parts[0]] = parts.get(1) ?? "?"
        }
        if (getVariable(UPDATE_EXPECT).isSome()) {
            let written = found.map { one => "${one}  # ${why.get(one) ?? "?"}" }
            File
                .writeTo(
                    knownOfStd(),
                    (String.join(header.concat(written), delimiter: "\n") + "\n").toArray()
                )
            return
        }
        let known = why.keys().toArray()
        sort(known)
        @Expect(found, known)
    }
}

/**
 * This repository's roots of an error type (`InferenceCensusTest`'s), as many in each file of each
 * kind as `error_roots_known.txt` says: each a false error of the analysis on a source cjc accepts,
 * which no diagnostic need show. Linux's alone: the target picks which files of a source set are read
 * (D99). The pass after `DiagnosticsGateTest`'s reads what it inferred (D108).
 */
@When[os == "Linux"]
@Test
@Tag[gate]
@Timeout[Duration.minute * 5]
class ErrorRootsGateTest {
    /**
     * A count grown fails with where each root of it is; one shrunk until `UPDATE_EXPECT=1` writes it,
     * so the file only shrinks.
     */
    @TestCase
    func thisRepositoryHasOnlyTheErrorRootsOfKnownGaps() {
        // arrange
        let ws = workspace()
        let lines =
            String.fromUtf8(File.readFrom(knownErrorRoots())).replace("\r\n", "\n").split("\n")
        let baseline = ErrorRootBaseline(lines)

        // act
        let byLine = HashMap<String, ArrayList<ErrorRoot>>()
        for (root in censusOf(ws).errorRoots) {
            let line =
                "${relativeName(ws.paths.path(root.file.fileId(ws.db)), workspaceRoot())}: ${root.kind}"
            let roots = byLine.get(line) ?? ArrayList<ErrorRoot>()
            roots.add(root)
            byLine[line] = roots
        }
        let found = HashMap(byLine.toArray().map { entry => (entry[0], entry[1].size) })

        if (getVariable(UPDATE_EXPECT).isSome()) {
            let written = baseline.updated(found)
            let text = String.join(written, delimiter: "\n")
            File.writeTo(knownErrorRoots(), "${text}\n".toArray())
            return
        }

        // assert
        let known = baseline.counts
        let changed = ArrayList<String>()
        for (line in baseline.unattributedLocals()) {
            changed.add("${line}: attribute each local root to its gap's issue (#425)")
        }
        for (
            (line, count) in found where count >
                (known.get(line) ?? 0)
        ) {
            let roots = byLine[line].toArray().map { root => whereIs(ws, root) }
            changed
                .add(
                    "${line}: ${known.get(line) ?? 0} known, ${count} found: ${String.join(roots, delimiter: "; ")}"
                )
        }
        for (
            (line, count) in known where count >
                (found.get(line) ?? 0)
        ) {
            changed
                .add(
                    "${line}: ${count} known, ${found.get(line) ?? 0} found: a gap closed, `UPDATE_EXPECT=1` takes it off"
                )
        }
        let sorted = changed.toArray()
        sort(sorted)
        // a text, not an array: an array's `@Expect` of another size tells the sizes alone
        @Expect(String.join(sorted, delimiter: "\n"), "")
    }
}

/**
 * The file of this repository's roots of an error type, `path: kind: count  # why` each.
 */
func knownErrorRoots(): Path {
    workspaceRoot()
        .filePath
        .getOrThrow()
        .join("modules")
        .join("project_model")
        .join("error_roots_known.txt")
}

/**
 * `path` relative to `root`, with `/`s.
 */
func relativeName(path: VfsPath, root: VfsPath): String {
    path.toString().replace("\\", "/").removePrefix(root.toString().replace("\\", "/") + "/")
}

/**
 * The line of `root` and the start of its text.
 */
func whereIs(ws: BenchWorkspace, root: ErrorRoot): String {
    let db = ws.db
    let origin =
        bodyWithSourceMap(db, root.def).sourceMap.exprs.get(root.id.index) ?? return "no node"
    let source =
        match (origin) {
            case WrittenSource(source) => source
            case _ => return "no node"
        }
    let node = source.node(db, root.def.file(db)) ?? return "no node"
    let range =
        if (let Some(call) <- source.expansion) {
            sourceRangeOf(db, call, node.textRange) ??
                (macroCallHeadOf(db, call) ?? return "no call")[1]
        } else {
            node.textRange
        }
    let line = root.file.text(db).toString()[..range.start].count("\n") + 1
    let runes = node.text().replace("\n", " ").toRuneArray()
    let text = if (runes.size > 60) { String(runes[..60]) + "…" } else { String(runes) }
    "line ${line} `${text}`"
}
