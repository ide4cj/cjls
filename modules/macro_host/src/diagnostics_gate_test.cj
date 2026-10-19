package macro_host

import std.collection.*
import std.env.{getTempDirectory, getVariable, getWorkingDirectory}
import std.fs.*
import std.sort.sort
import std.unittest.*
import std.unittest.testmacro.*
import stdx.log.NoopLogger
import loupe.{diagnostics, Severity}
import loupe.db.*
import loupe.hir.{macroBuildPlan, setMacroOutputsByKey}
import loupe.vfs.{PathInterner, readCjoFiles, readFiles, Vfs, VfsPath}
import macro_server.MacroServerPaths
import project_model.findProject

/**
 * The root of this repository: the nearest directory above the tests' whose `cjpm.toml` is a workspace's.
 */
func repositoryRoot(): VfsPath {
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
 * This repository as the server loads it, and its members' files.
 */
func repository(root: VfsPath): (AnalysisDatabase, PathInterner, Array<SourceFile>) {
    let load = findProject(root, env: {name => getVariable(name)})
    let vfs = Vfs()
    let db = AnalysisDatabase()
    db.setProject(load.model, vfs.paths, binaries: readCjoFiles(load.model.cjoFiles()).files)
    for ((path, text) in readFiles(load.model.files()).files) {
        vfs.setFileContents(path, text)
    }
    db.applyChanges(vfs, vfs.takeChanges())
    let files = ArrayList<SourceFile>()
    for (module in db.project().getOrThrow().modules(db) where module.member(db)) {
        for (pkg in module.packages(db)) {
            for (fileId in pkg.files(db)) {
                if (let Some(file) <- db.sourceFile(fileId)) {
                    files.add(file)
                }
            }
        }
    }
    (db, vfs.paths, files.toArray())
}

/**
 * Builds the macro packages of `db` with the SDK's cjc into a fresh directory, as the server does (D104), and sets
 * the stamps of their libraries: the libraries, and why each that did not build did not.
 */
func buildMacros(db: AnalysisDatabase, paths: MacroServerPaths): (HashMap<Package, MacroLibrary>, Array<String>) {
    let toolchain = SdkToolchain(paths)
    let out = Directory.createTemp(getTempDirectory()).join("macro-build")
    let built = buildPlan(db, macroBuildPlan(db), {_ => out}, toolchain.version().getOrThrow(), toolchain)
    let libraries = HashMap<Package, MacroLibrary>()
    let failed = ArrayList<String>()
    db.batch {
        for ((pkg, result) in built.libraries) {
            match (result) {
                case Built(path, stamp) =>
                    libraries[pkg] = MacroLibrary(path.toString(), stamp)
                    pkg.setMacroLibrary(db).to(stamp)
                case NotBuilt(reason) => failed.add("${pkg.name(db)}: ${reason}")
            }
        }
    }
    (libraries, failed.toArray())
}

/**
 * Asks the SDK's macro server every call of `files` it can be sent, std's and the workspace's of `libraries`, until
 * none is left: an outer call is sent once the calls inside it are answered, as the server's host does.
 */
func expandAllCalls(db: AnalysisDatabase, files: Array<SourceFile>, libraries: HashMap<Package, MacroLibrary>,
    paths: MacroServerPaths): Unit {
    let servers = MacroServers(paths, Duration.minute, NoopLogger())
    try {
        while (true) {
            let requests = sendableRequests(db, files, libraries,
                stdLibrary: {pkg => paths.stdMacroLibrary(pkg).map {path => path.toString()}})
            if (requests.isEmpty()) {
                break
            }
            setMacroOutputsByKey(db, expandAll(db, requests, testNumbers(), servers))
        }
    } finally {
        servers.close()
    }
}

/**
 * `project_model`'s `DiagnosticsGateTest` as an editor reads this repository (#434, D132): every call of a macro on
 * an item, std's (`@Derive`, `@Test`, `@TestCase`) and the workspace's (`@DeriveExt`), expanded by the SDK's macro
 * server, and every body inferred through its output. A false error of reading an output fails it, named: the bugs
 * of #430 and #431 hid while the gate read cjls's own expansions of std alone. What it costs beyond that gate is a
 * build of the macro packages and a round trip per call, a few seconds of the half minute the inference takes, so
 * the outputs are asked of the SDK each run, never recorded. Tagged `gate`: the coverage run leaves it out (D120).
 */
@Test
@Tag[gate]
@Timeout[Duration.minute * 10]
class ServedDiagnosticsGateTest {
    @TestCase
    func thisRepositoryHasNoDiagnosticWithItsMacrosExpandedByTheServer() {
        // arrange
        let root = repositoryRoot()
        let (db, interner, files) = repository(root)
        let paths = testSdkPaths()
        let (libraries, failed) = buildMacros(db, paths)
        @Assert(failed, Array<String>())

        // act
        expandAllCalls(db, files, libraries, paths)

        // assert
        let found = ArrayList<String>()
        for (file in files) {
            let text = file.text(db).toString()
            let name = interner.path(file.fileId(db)).toString().replace("\\", "/").removePrefix(
                root.toString().replace("\\", "/") + "/")
            for (one in diagnostics(db, file.fileId(db)) where one.severity != Severity.Hint) {
                found.add("${name}:${text[..one.range.start].count("\n") + 1}: ${one.message}")
            }
        }
        let sorted = found.toArray()
        sort(sorted)
        @Expect(sorted, Array<String>())
    }
}
