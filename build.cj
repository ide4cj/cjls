// cjpm runs this around every build and test. Builds are incremental (`[profile.build]` in
// cjpm.toml), and cjpm's cache knows a package by its sources' mtimes alone, not by the compiler:
// under another SDK it keeps every package the last one compiled, and links the new ones against
// them. So a build under a cjc other than the last one's starts from scratch (D27).
import std.env.*
import std.fs.*
import std.process.*

const TARGET = "target"
const STAMP = "target/cjc-version"
const CACHE = "incremental-cache.json"

main(): Int64 {
    if (getCommandLine().get(1) == "pre-build") {
        forgetAnotherCompiler()
    }
    0
}

func forgetAnotherCompiler(): Unit {
    let version = compilerVersion()
    if (let Some(v) <- version && exists(STAMP) && String.fromUtf8(File.readFrom(STAMP)) == v) {
        return
    }
    if (exists(TARGET)) {
        forgetCaches(Path(TARGET))
    } else {
        Directory.create(TARGET)
    }
    match (version) {
        case Some(v) => File.writeTo(STAMP, v.toArray())
        // not knowing is not the same compiler: the next build starts from scratch too
        case None =>
            if (exists(STAMP)) {
                remove(STAMP)
            }
    }
}

// one per target directory and profile, and one for the test binaries under it
func forgetCaches(dir: Path): Unit {
    for (entry in Directory.readFrom(dir)) {
        if (entry.isDirectory()) {
            forgetCaches(entry.path)
        } else if (entry.name == CACHE) {
            remove(entry.path)
        }
    }
}

// the cjc cjpm runs, the one on PATH
func compilerVersion(): ?String {
    try {
        let (code, out, _) = executeWithOutput("cjc", ["--version"])
        if (code == 0) {
            String.fromUtf8(out)
        } else {
            None
        }
    } catch (e: Exception) {
        None
    }
}
