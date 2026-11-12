package loupe.fixture

import std.env.{getTempDirectory, getVariable}
import std.fs.*
import std.process.executeWithOutput
import std.time.DateTime
import loupe.db.{BinaryModel, BinarySources, PackageModel}
import loupe.vfs.{CjoFile, CjoFileRead, FileStamp, VfsPath, isCangjieFile}

/**
 * The bytes of `<name>.cjo` of the SDK's std, of whichever target it has first.
 */
public func stdCjo(name: String): Array<Byte> {
    let home = Path(
        getVariable("CANGJIE_HOME") ?? throw IllegalStateException("CANGJIE_HOME names no SDK")
    )
    for (
        target in Directory.readFrom(canonicalize(home.join("modules"))) where FileInfo(
            canonicalize(target.path)
        )
            .isDirectory()
    ) {
        let file = target.path.join("std").join("${name}.cjo")
        if (exists(file)) {
            return File.readFrom(file)
        }
    }
    throw IllegalStateException("no ${name}.cjo under ${home.join("modules")}")
}

/**
 * `bytes` as the `.cjo` of the package `name` of `std`, read: what a project's binaries are.
 */
public func stdCjoRead(name: String, bytes: Array<Byte>): CjoFileRead {
    let file = CjoFile("std", name, VfsPath.file(getTempDirectory().join("${name}.cjo")))
    CjoFileRead(file, FileStamp(bytes.size, DateTime.now()), bytes)
}

/**
 * The directory of std's sources the SDK was built from, `cangjie_runtime`'s `stdlib/libs/std` at the
 * commit `tests/corpora/fetch.py` names: what a test of the sources of a binary reads.
 */
public func stdSourcesDir(): VfsPath {
    let dir = Path(
        getVariable("CJLS_TEST_STD_SOURCES") ?? ".corpora/cangjie_runtime/stdlib/libs/std"
    )
    if (!exists(dir)) {
        throw IllegalStateException(
            "cangjie_runtime is not in .corpora/: run `python3 tests/corpora/fetch.py`"
        )
    }
    VfsPath.file(canonicalize(dir))
}

/**
 * `std` with the sources of its packages `names`, each the `*.cj` of the directory its name gives.
 */
public func stdWithSources(names: Array<String>): BinaryModel {
    let dir = stdSourcesDir()
    let packages =
        names
            .map {
                name =>
                let pkgDir =
                    name
                        .split(".")[1..]
                        .iterator()
                        .fold(dir) { path, segment => path.join(segment) }
                let files =
                    Directory
                        .readFrom(pkgDir.filePath.getOrThrow())
                        .filter { info => info.isRegular() && isCangjieFile(info.name) }
                        .map { info => pkgDir.join(info.name) }
                PackageModel(name, pkgDir, files)
            }
    BinaryModel("std", [], sources: BinarySources(dir, packages))
}

/**
 * The compiler version of the SDK whose std the tests read, rather than the build's pin.
 */
public func stdCompilerVersion(): String {
    let home =
        getVariable("CANGJIE_HOME") ?? throw IllegalStateException("CANGJIE_HOME names no SDK")
    let bin = Path(home).join("bin")
    let compiler = if (exists(bin.join("cjc.exe"))) { "cjc.exe" } else { "cjc" }
    let (code, output, _) = executeWithOutput(bin.join(compiler).toString(), ["--version"])
    if (code != 0) {
        throw IllegalStateException("${bin}: cjc --version failed")
    }
    let prefix = "Cangjie Compiler: "
    let text = String.fromUtf8(output)
    if (!text.startsWith(prefix)) {
        throw IllegalStateException("unrecognized cjc version: ${text}")
    }
    text[prefix.size..].split(" ")[0]
}
