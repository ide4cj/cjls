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
import loupe.hir.{macroBuildPlan, macroCallHeadOf, macroOutputOf, serverCalls, setMacroOutputsByKey}
import loupe.vfs.{readCjoFiles, readFiles, Vfs, VfsPath}
import project_model.findProject

/**
 * The workspace at `root` loaded as the server loads a project, its macro packages built by the SDK's cjc into a fresh directory and
 * every call of its files expanded by the macro server, round by round until none is left to send, as `MacroHost`
 * does (D104): what the gate finds, each diagnostic of its files as `path:line: message`, a failed call's among them,
 * and each call the server runs that was never sent as `path:line: @name never sent`; a macro package cjc did not
 * build as `package: not built: why`; sorted.
 */
func gateFindings(root: VfsPath): Array<String> {
    let load = findProject(root, env: { name => getVariable(name) })
    let db = AnalysisDatabase()
    let vfs = Vfs()
    db.setProject(load.model, vfs.paths, binaries: readCjoFiles(load.model.cjoFiles()).files)
    for ((path, text) in readFiles(load.model.files()).files) {
        vfs.setFileContents(path, text)
    }
    db.applyChanges(vfs, vfs.takeChanges())
    let files =
        load.model.files() |>
            filterMap {
                path: VfsPath =>
                vfs.paths.lookup(path).flatMap { id => db.sourceFile(id) }
            } |>
            collectArray

    let paths = testSdkPaths()
    let toolchain = SdkToolchain(paths)
    let version = toolchain.version().getOrThrow()
    let out = Directory.createTemp(getTempDirectory()).join("macro-build")
    let built = buildPlan(db, macroBuildPlan(db), { _ => out }, version, toolchain)
    let found = ArrayList<String>()
    let libraries = HashMap<Package, MacroLibrary>()
    for ((pkg, result) in built.libraries) {
        match (result) {
            case Built(library, stamp) => libraries[pkg] = MacroLibrary(library.toString(), stamp)
            case NotBuilt(reason) =>
                found.add("${pkg.name(db)}: not built: ${reason.split("\n")[0]}")
        }
    }
    db
        .batch {
            for ((pkg, library) in libraries) {
                pkg.setMacroLibrary(db).to(library.stamp)
            }
        }

    let servers = MacroServers(paths, Duration.minute, NoopLogger())
    try {
        while (true) {
            let requests =
                sendableRequests(
                    db,
                    files,
                    libraries,
                    stdLibrary: {
                        pkg =>
                        paths.stdMacroLibrary(pkg).map { path => path.toString() }
                    }
                )
            if (requests.isEmpty()) {
                break
            }
            setMacroOutputsByKey(db, expandAll(db, requests, testNumbers(), servers))
        }
    } finally {
        servers.close()
    }
    for (file in files) {
        let text = file.text(db).toString()
        let name = nameIn(vfs.paths.path(file.fileId(db)), root)
        for (one in diagnostics(db, file.fileId(db)) where one.severity != Severity.Hint) {
            found.add("${name}:${text[..one.range.start].count("\n") + 1}: ${one.message}")
        }
        // a call that failed has its diagnostic; one never sent has nothing to show it
        for (call in serverCalls(db, file) where macroOutputOf(db, call.call).isNone()) {
            let line =
                macroCallHeadOf(db, call.call)
                    .map { head => "${text[..head[1].start].count("\n") + 1}" } ??
                    "?"
            found.add("${name}:${line}: @${call.definition.name} never sent")
        }
    }
    let sorted = found.toArray()
    sort(sorted)
    sorted
}

/**
 * `path` relative to `root`, with `/`s.
 */
func nameIn(path: VfsPath, root: VfsPath): String {
    path.toString().replace("\\", "/").removePrefix(root.toString().replace("\\", "/") + "/")
}

/**
 * `project_model`'s `DiagnosticsGateTest` as an editor reads this repository (#434, D132): every call of a macro on
 * an item, std's (`@Derive`, `@Test`, `@TestCase`) and the workspace's (`@DeriveExt`), expanded by the SDK's macro
 * server, and every body inferred through its output, finds nothing. A false error of reading an output fails it,
 * named: the bugs of #430 and #431 hid while the gate read cjls's own expansions of std alone. What it costs beyond
 * that gate is a build of the macro packages and a round trip per call, a few seconds of the half minute the
 * inference takes, so the outputs are asked of the SDK each run, never recorded. Tagged `gate`: the coverage run
 * leaves it out (D120).
 */
@Test
@Tag[gate]
@Timeout[Duration.minute * 10]
class ServedDiagnosticsGateTest {
    @TestCase
    func thisRepositoryHasNoFindingWithItsMacrosExpandedByTheServer() {
        // act
        let found = gateFindings(VfsPath.file(getWorkingDirectory()))

        // assert
        // a text, not an array: an array's `@Expect` of another size tells the sizes alone
        @Expect(String.join(found, delimiter: "\n"), "")
    }
}
