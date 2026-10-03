package project_model

import std.collection.*
import std.fs.*
import std.sort.*
import loupe.db.{BinaryPackageModel, ProjectModel}
import loupe.vfs.VfsPath

/**
 * A Cangjie SDK found, and where from: `std` is in it, and `${CANGJIE_HOME}` expands to it.
 */
public struct CangjieHome {
    public CangjieHome(
        public let path: String,
        /**
         * What named it, for the log: `initializationOptions.cangjieHome`, `CANGJIE_HOME`, cjsdk's
         * default toolchain, or `cjc` on `PATH`.
         */
        public let source: String
    ) {}
}

/**
 * The SDK, the first of these that is a directory: `option` (`initializationOptions.cangjieHome`,
 * which the editor takes from a setting of its own); `CANGJIE_HOME`; cjsdk's default toolchain,
 * `~/.cjpm/toolchains/default`; and the directory two up from `cjc` on `PATH`, links followed
 * (`<home>/bin/cjc`). `None` if none is: an editor launches the server with the environment of the
 * desktop, which `envsetup.sh` never touched.
 *
 * `env` gives the value of an environment variable.
 */
public func findCangjieHome(option: ?String, env!: (String) -> ?String): ?CangjieHome {
    let home = match (env("HOME")) {
        case Some(home) => home
        case None => env("USERPROFILE")
    }
    let candidates: Array<(?String, String)> = [
        (option, "initializationOptions.cangjieHome"),
        (env("CANGJIE_HOME"), "CANGJIE_HOME"),
        (home.map {it => Path(it).join(".cjpm").join("toolchains").join("default").toString()},
            "the default toolchain of cjsdk"),
        (cjcOnPath(env("PATH") ?? "").flatMap {cjc => cjc.parent.parent.toString()}, "cjc on PATH")
    ]
    for ((path, source) in candidates) {
        if (let Some(path) <- path) {
            if (isDirectory(path)) {
                return CangjieHome(path, source)
            }
        }
    }
    None
}

/**
 * `env` with `CANGJIE_HOME` the SDK found, `None` if none is: what `${CANGJIE_HOME}` expands to in a
 * path, and where `std` is taken from, whatever the environment says.
 */
public func withCangjieHome(env: (String) -> ?String, home: ?CangjieHome): (String) -> ?String {
    let path = home.map {it => it.path}
    {
        name: String => if (name == "CANGJIE_HOME") {
            path
        } else {
            env(name)
        }
    }
}

/**
 * `cjc` in the first directory of `path` that has it, its links followed, `None` if none has.
 */
func cjcOnPath(path: String): ?Path {
    let separator = if (HOST_OS == "Windows") {
        ";"
    } else {
        ":"
    }
    let name = if (HOST_OS == "Windows") {
        "cjc.exe"
    } else {
        "cjc"
    }
    for (dir in path.split(separator) where !dir.isEmpty() && Path(dir).isAbsolute()) {
        let cjc = Path(dir).join(name)
        try {
            if (exists(cjc)) {
                return canonicalize(cjc)
            }
        } catch (_: FSException) {
            continue
        }
    }
    None
}

func isDirectory(path: String): Bool {
    Path(path).isAbsolute() && (try {
        exists(path) && FileInfo(path).isDirectory()
    } catch (_: FSException) {
        false
    })
}

/**
 * The packages of `model`'s binaries, each once per binary: every `*.cjo` right in a directory of
 * its `paths`, named after the file (`std.core.cjo` is `std.core`), then those it names one by one,
 * in place of one of the same name. A directory that cannot be listed has none.
 */
public func binaryPackagesOf(model: ProjectModel): Array<BinaryPackageModel> {
    let packages = ArrayList<BinaryPackageModel>()
    for (binary in model.binaries) {
        let byName = HashMap<String, VfsPath>()
        let names = ArrayList<String>()
        let found = binary.paths.map {dir => cjoFilesIn(dir)}.flatMap {files => files}.map {
            file => (file.name.removeSuffix(".cjo"), file)
        }.concat(binary.packages.map {pkg => (pkg.name, pkg.path)})
        for ((name, path) in found) {
            if (byName.add(name, path).isNone()) {
                names.add(name)
            }
        }
        packages.add(all: names.toArray().map {name => BinaryPackageModel(binary.name, name, byName[name])})
    }
    packages.toArray()
}

/**
 * The `*.cjo` right in `dir`, in the order of their names; none if it cannot be listed.
 */
func cjoFilesIn(dir: VfsPath): Array<VfsPath> {
    let path = dir.filePath ?? return []
    let entries = try {
        Directory.readFrom(path)
    } catch (_: FSException) {
        return []
    }
    let files = entries.filter {entry => entry.isRegular() && entry.name.endsWith(".cjo")}.map {
        entry => VfsPath.file(entry.path)
    }
    sort(files, by: {a, b => a.toString().compare(b.toString())})
    files
}
