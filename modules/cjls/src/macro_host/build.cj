package cjls.macro_host

import std.collection.*
import std.convert.*
import std.fs.*
import std.sort.sort
import std.time.DateTime
import platform.sharedLibrarySuffix
import cjls.server.tryLockCacheDir

/**
 * A package cjls builds for the macro server (`loupe`'s `MacroBuildUnit`, as paths): its name, its module, the
 * directory of its sources, whether it is a macro package, the source packages it links (each `(module, name)`,
 * built before it) and the `.cjo` of the binaries it imports.
 */
public struct BuildUnit {
    public BuildUnit(
        public let name: String,
        public let module: String,
        public let dir: Path,
        public let isMacro: Bool,
        public let deps: Array<(String, String)>,
        public let binaries: Array<Path>
    ) {}
}

/**
 * What building a macro package gave: its library and the stamp of what it was built of, which changes whenever
 * the library does; or why there is none.
 */
public enum BuiltLibrary {
    | Built(Path, Int64)
    | NotBuilt(String)
}

/**
 * Runs the SDK's `cjc`: a test's is a fake.
 */
public interface Toolchain {
    /**
     * Runs `cjc` with `arguments`: its exit code and what it wrote to stderr and stdout.
     */
    func compile(arguments: Array<String>): (Int64, String)
}

/**
 * Builds the macro packages of the workspace and the source packages they link into `out` (D104): `<out>/<module>`
 * holds each package's `.cjo` and its library, `lib-macro_<pkg>` for a macro package, `lib<pkg>.a` for another,
 * and the stamp of what it was built of; a package whose stamp did not change is not built again. As cjpm does it,
 * with `--compile-macro` for a macro package, without its `build.cj` and without any other package. A build holds
 * `out`'s lock (`tryLockCacheDir`, D106), so a second server on the project neither builds there at once nor
 * removes it meanwhile.
 */
public class MacroBuilder {
    public MacroBuilder(private let out: Path, private let version: String, private let toolchain: Toolchain) {}

    /**
     * Builds `units`, in their order: for each macro package, by name, its library, or why there is none. A package
     * whose dependency did not build is not built either. `None`, nothing built, while another holds `out`'s lock:
     * what it builds is found by its stamps the next time.
     *
     * @throws FSException - if `out`'s lock file cannot be opened
     */
    public func build(units: Array<BuildUnit>): ?HashMap<String, BuiltLibrary> {
        let lock = tryLockCacheDir(out) ?? return None
        try {
            buildAll(units)
        } finally {
            lock.close()
        }
    }

    private func buildAll(units: Array<BuildUnit>): HashMap<String, BuiltLibrary> {
        let stamps = HashMap<String, Int64>()
        let failed = HashMap<String, String>()
        let built = HashMap<String, BuiltLibrary>()
        for (unit in units) {
            let result = buildOne(unit, stamps, failed)
            match (result) {
                case Built(_, stamp) => stamps[unit.name] = stamp
                case NotBuilt(reason) => failed[unit.name] = reason
            }
            if (unit.isMacro) {
                built[unit.name] = result
            }
        }
        built
    }

    private func buildOne(unit: BuildUnit, stamps: HashMap<String, Int64>, failed: HashMap<String, String>): BuiltLibrary {
        for ((_, dep) in unit.deps) {
            if (failed.contains(dep)) {
                return NotBuilt("${dep}, which it imports, did not build")
            }
        }
        let dir = out.join(unit.module)
        let output = dir.join(outputName(unit))
        let stampFile = dir.join("${unit.name}.stamp")
        let stamp = stampOf(unit, stamps)
        if (exists(output) && readStamp(stampFile) == Some(stamp)) {
            return Built(output, stamp)
        }
        try {
            // `create` throws for a directory that is there
            if (!exists(dir)) {
                Directory.create(dir, recursive: true)
            }
        } catch (e: FSException) {
            return NotBuilt("${dir} cannot be made: ${e.message}")
        }
        let (code, said) = toolchain.compile(argumentsOf(unit))
        if (code != 0 || !exists(output)) {
            return NotBuilt(if (said.isEmpty()) {
                "cjc exited with ${code}"
            } else {
                said
            })
        }
        try {
            File.writeTo(stampFile, "${stamp}".toArray())
        } catch (_: Exception) {
            ()
        }
        Built(output, stamp)
    }

    /**
     * cjc's arguments for `unit`, as cjpm's own: the package alone, what it imports found in `out` and next to the
     * `.cjo` of its binaries.
     */
    func argumentsOf(unit: BuildUnit): Array<String> {
        let arguments = ArrayList<String>(["-p", unit.dir.toString(), "--import-path=${out}", "--no-sub-pkg",
            "--output-dir=${out.join(unit.module)}"])
        let binaryDirs = ArrayList<Path>()
        for (cjo in unit.binaries) {
            if (let Some(parent) <- parentOf(cjo) && !binaryDirs.contains(parent)) {
                binaryDirs.add(parent)
                arguments.add("--import-path=${parent}")
            }
        }
        if (unit.isMacro) {
            for ((module, dep) in unit.deps) {
                arguments.add(all: ["-L", out.join(module).toString(), "-l${dep}"])
            }
            for (cjo in unit.binaries) {
                if (let Some(parent) <- parentOf(cjo)) {
                    arguments.add(all: ["-L", parent.toString(), "-l${stemOf(cjo)}"])
                }
            }
            arguments.add("--compile-macro")
        } else {
            arguments.add(all: ["--output-type=staticlib", "-o=lib${unit.name}.a"])
        }
        arguments.toArray()
    }

    /**
     * What tells one build of `unit` from another: cjc's version, its sources (their names, sizes and times), and
     * the stamps of what it links.
     */
    private func stampOf(unit: BuildUnit, stamps: HashMap<String, Int64>): Int64 {
        let text = StringBuilder(version)
        for (file in sourcesOf(unit.dir)) {
            text.append("\u{0}${file}")
        }
        for ((_, dep) in unit.deps) {
            text.append("\u{0}${dep}=${stamps.get(dep) ?? 0}")
        }
        for (cjo in unit.binaries) {
            text.append("\u{0}${cjo}=${timeOf(cjo)}")
        }
        text.toString().hashCode()
    }
}

/**
 * The file `unit`'s build writes last: its library.
 */
func outputName(unit: BuildUnit): String {
    if (unit.isMacro) {
        "lib-macro_${unit.name}${sharedLibrarySuffix()}"
    } else {
        "lib${unit.name}.a"
    }
}

/**
 * The `.cj` files directly in `dir`, each as its name, size and time, in the order of their names.
 */
func sourcesOf(dir: Path): Array<String> {
    let found = ArrayList<String>()
    try {
        for (entry in Directory.readFrom(dir) where entry.isRegular() && entry.name.endsWith(".cj")) {
            found.add("${entry.name}:${entry.size}:${timeOf(entry.path)}")
        }
    } catch (_: Exception) {
        ()
    }
    let sorted = found.toArray()
    sort(sorted)
    sorted
}

func timeOf(path: Path): Int64 {
    try {
        (FileInfo(path).lastModificationTime - DateTime.UnixEpoch).toNanoseconds()
    } catch (_: Exception) {
        0
    }
}

func readStamp(file: Path): ?Int64 {
    try {
        Int64.parse(String.fromUtf8(File.readFrom(file)))
    } catch (_: Exception) {
        None
    }
}

func parentOf(path: Path): ?Path {
    try {
        path.parent
    } catch (_: Exception) {
        None
    }
}

/**
 * `stdx.log` of `.../stdx.log.cjo`.
 */
func stemOf(cjo: Path): String {
    let name = cjo.fileName
    if (name.endsWith(".cjo")) {
        name[..name.size - 4]
    } else {
        name
    }
}
