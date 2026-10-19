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
import loupe.fixture.UPDATE_EXPECT
import loupe.hir.{macroBuildPlan, macroCallHeadOf, macroOutputOf, serverCalls, setMacroOutputsByKey}
import loupe.vfs.{readCjoFiles, readFiles, Vfs, VfsPath}
import project_model.findProject

/**
 * Optics (`.corpora/`, at the commit `tests/corpora/fetch.py` names): a workspace of others' written on its own
 * macros, which change without us.
 */
func opticsDir(): VfsPath {
    let dir = getWorkingDirectory().join(".corpora").join("Optics")
    if (!exists(dir.join("cjpm.toml"))) {
        throw IllegalStateException("Optics is not in .corpora/: run `python3 tests/corpora/fetch.py`")
    }
    VfsPath.file(dir)
}

/**
 * The file of what the gate finds on Optics and why, a line `path:line: message  # why` each.
 */
func knownOfOptics(): Path {
    getWorkingDirectory().join("modules").join("macro_host").join("optics_diagnostics_known.txt")
}

/**
 * Optics loaded as the server loads a project, its macro packages built by the SDK's cjc into a fresh directory and
 * every call of its files expanded by the macro server, round by round until none is left to send, as `MacroHost`
 * does (D104): what the gate finds, each diagnostic of its files as `path:line: message`, a failed call's among them,
 * and each call the server runs that was never sent as `path:line: @name never sent`; a macro package cjc did not
 * build as `package: not built: why`; sorted.
 */
func opticsFindings(): Array<String> {
    let root = opticsDir()
    let load = findProject(root, env: {name => getVariable(name)})
    let db = AnalysisDatabase()
    let vfs = Vfs()
    db.setProject(load.model, vfs.paths, binaries: readCjoFiles(load.model.cjoFiles()).files)
    for ((path, text) in readFiles(load.model.files()).files) {
        vfs.setFileContents(path, text)
    }
    db.applyChanges(vfs, vfs.takeChanges())
    let files = load.model.files() |> filterMap {path: VfsPath => vfs.paths.lookup(path).flatMap {id => db.sourceFile(id)}} |>
        collectArray

    let paths = testSdkPaths()
    let toolchain = SdkToolchain(paths)
    let version = toolchain.version().getOrThrow()
    let out = Directory.createTemp(getTempDirectory()).join("macro-build")
    let built = buildPlan(db, macroBuildPlan(db), {_ => out}, version, toolchain)
    let found = ArrayList<String>()
    let libraries = HashMap<Package, MacroLibrary>()
    for ((pkg, result) in built.libraries) {
        match (result) {
            case Built(library, stamp) => libraries[pkg] = MacroLibrary(library.toString(), stamp)
            case NotBuilt(reason) => found.add("${pkg.name(db)}: not built: ${reason.split("\n")[0]}")
        }
    }
    db.batch {
        for ((pkg, library) in libraries) {
            pkg.setMacroLibrary(db).to(library.stamp)
        }
    }

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
    for (file in files) {
        let text = file.text(db).toString()
        let name = nameIn(vfs.paths.path(file.fileId(db)), root)
        for (one in diagnostics(db, file.fileId(db)) where one.severity != Severity.Hint) {
            found.add("${name}:${text[..one.range.start].count("\n") + 1}: ${one.message}")
        }
        // a call that failed has its diagnostic; one never sent has nothing to show it
        for (call in serverCalls(db, file) where macroOutputOf(db, call.call).isNone()) {
            let line = macroCallHeadOf(db, call.call).map {head => "${text[..head[1].start].count("\n") + 1}"} ?? "?"
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
 * A workspace on macros of its own expands and analyzes as cjc compiles it: Optics, built clean by the SDK of
 * `.cangjie-version`, has the findings `optics_diagnostics_known.txt` lists, no more and no fewer. A new one is a
 * false error of the expansion or the analysis, one gone a gap closed, to take off the list, which only shrinks.
 * `UPDATE_EXPECT=1` writes it, keeping the why of each line still found; a new one's `?` is to be written. Tagged
 * `gate`: the coverage run leaves it out (D120).
 */
@Test
@Tag[gate]
@Timeout[Duration.minute * 10]
class OpticsGateTest {
    @TestCase
    func opticsHasOnlyTheFindingsOfKnownGaps() {
        let found = opticsFindings()
        let lines = String.fromUtf8(File.readFrom(knownOfOptics())).replace("\r\n", "\n").split("\n")
        let header = lines.filter {line => line.startsWith("#")}
        let why = HashMap<String, String>()
        for (line in lines where !line.startsWith("#") && !line.isEmpty()) {
            let parts = line.split("  # ", 2)
            why[parts[0]] = parts.get(1) ?? "?"
        }
        if (getVariable(UPDATE_EXPECT).isSome()) {
            let written = found.map {one => "${one}  # ${why.get(one) ?? "?"}"}
            File.writeTo(knownOfOptics(), (String.join(header.concat(written), delimiter: "\n") + "\n").toArray())
            return
        }
        let known = why.keys().toArray()
        sort(known)
        // a text, not an array: an array's `@Expect` of another size tells the sizes alone
        @Expect(String.join(found, delimiter: "\n"), String.join(known, delimiter: "\n"))
    }
}
