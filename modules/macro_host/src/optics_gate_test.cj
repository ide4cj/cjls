package macro_host

import std.collection.*
import std.env.{getVariable, getWorkingDirectory}
import std.fs.*
import std.sort.sort
import std.unittest.*
import std.unittest.testmacro.*
import loupe.fixture.UPDATE_EXPECT
import loupe.vfs.VfsPath

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
        let found = gateFindings(opticsDir())
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
