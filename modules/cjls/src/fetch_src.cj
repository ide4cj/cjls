package cjls

import std.fs.{Directory, File, FileInfo, FSException, Path, exists, removeIfExists, rename}
import std.io.OutputStream
import std.process.{ProcessException, executeWithOutput}

/**
 * Where a nightly's release notes are read, by its tag (the version `cjc --version` prints): the
 * GitHub mirror's API first, then gitcode's, the origin (D62).
 */
let RELEASE_NOTES = [
    "https://api.github.com/repos/cangjie-bot/nightly_build/releases/tags/",
    "https://api.gitcode.com/api/v5/repos/Cangjie/nightly_build/releases/tags/"
]

/**
 * Where `cangjie_runtime` is downloaded at a commit, as a `.tar.gz`: GitHub's mirror alone, gitcode's
 * archives asking for a login.
 */
const RUNTIME_ARCHIVE = "https://github.com/cangjie-bot/cangjie_runtime/archive/"

/**
 * The file in the sources that names the commit of `cangjie_runtime` they are of: what tells them
 * from a directory of the user's, and a fetch already done.
 */
const SRC_STAMP = "cangjie_runtime.commit"

/**
 * The file of `cjc` in the SDK's `bin`.
 */
@When[os == "Windows"]
const CJC = "cjc.exe"

@When[os != "Windows"]
const CJC = "cjc"

/**
 * What fetching the sources takes from outside the process: the network, `tar`, the SDK's `cjc`.
 * A test's is a fake.
 */
interface SrcHost {
    /**
     * What `cjc --version` prints, `None` if it does not run.
     */
    func compilerVersion(cjc: Path): ?String

    /**
     * The body `url` answers, `None` on a failure.
     */
    func get(url: String): ?String

    /**
     * Downloads `url` into the file `to`; `false` on a failure.
     */
    func download(url: String, to: Path): Bool

    /**
     * Unpacks the `.tar.gz` `archive` into the directory `into`; `false` on a failure.
     */
    func unpack(archive: Path, into: Path): Bool
}

/**
 * The host's own `curl` and `tar`, which Windows 10, macOS and Linux all ship.
 */
class SystemSrcHost <: SrcHost {
    public func compilerVersion(cjc: Path): ?String {
        run(cjc.toString(), ["--version"], None)
    }

    public func get(url: String): ?String {
        run("curl", ["-fsSL", "--retry", "2", url], None)
    }

    public func download(url: String, to: Path): Bool {
        // a name relative to the directory, as `unpack`'s
        let dir = to.parent
        run("curl", ["-fsSL", "--retry", "2", "-o", to.fileName, url], dir).isSome()
    }

    public func unpack(archive: Path, into: Path): Bool {
        // relative: GNU tar, first on `PATH` in Git's shell on Windows, takes `C:\…` for a host
        run("tar", ["-xzf", archive.toString()], into).isSome()
    }

    /**
     * What `command` prints, `None` if it does not run or fails; what it says on stderr goes to ours.
     */
    private func run(command: String, arguments: Array<String>, dir: ?Path): ?String {
        try {
            let (exitCode, out, _) = executeWithOutput(command, arguments, workingDirectory: dir)
            if (exitCode == 0) {
                String.fromUtf8(out)
            } else {
                None
            }
        } catch (_: ProcessException) {
            None
        }
    }
}

/**
 * Puts the sources of `std` of the SDK at `home` into `dir`, laid out as `cangjie_runtime`'s
 * `stdlib/libs`, as `findCangjieSrc` looks for them (D65, D69): the commit of `cangjie_runtime` is the
 * one the release notes of the SDK's nightly name, its version what `cjc --version` prints. Nothing
 * is downloaded if `dir` is of that commit already; a `dir` holding something else is left alone.
 * What it does goes to `err`, the directory filled to `out`.
 *
 * @return the exit code: `1` if the SDK's version or its commit is not found, the download or the
 * unpacking fails, or `dir` holds something else
 */
func fetchSrc(home: Path, dir: Path, host: SrcHost, out: OutputStream, err: OutputStream): Int64 {
    let code = fetchSrcTo(home, dir, host, err)
    if (code == 0) {
        out.write("${dir}\n".toArray())
    }
    out.flush()
    err.flush()
    code
}

func fetchSrcTo(home: Path, dir: Path, host: SrcHost, err: OutputStream): Int64 {
    let say = {line: String => err.write("${line}\n".toArray())}
    let cjc = home.join("bin").join(CJC)
    let version = match (host.compilerVersion(cjc).flatMap {it => compilerVersionOf(it)}) {
        case Some(version) => version
        case None =>
            say("${cjc}: no version: is ${home} an SDK?")
            return 1
    }
    let commit = match (runtimeCommitOfRelease(version, host)) {
        case Some(commit) => commit
        case None =>
            say("no release notes of a nightly ${version} name its cangjie_runtime: a release SDK's sources are not fetched; put std's in a directory and name it by CANGJIE_SRC")
            return 1
    }
    if (stampOf(dir) == Some(commit)) {
        say("${dir}: std's sources of ${version} already, cangjie_runtime ${commit}")
        return 0
    }
    if (holdsOther(dir)) {
        say("${dir}: not replaced: it holds no sources fetched by cjls (no ${SRC_STAMP})")
        return 1
    }
    let part = Path("${dir}.part")
    try {
        removeIfExists(part, recursive: true)
        Directory.create(part, recursive: true)
        let archive = part.join("cangjie_runtime.tar.gz")
        let url = "${RUNTIME_ARCHIVE}${commit}.tar.gz"
        say("downloading ${url}")
        if (!host.download(url, archive)) {
            say("${url}: not downloaded")
            return 1
        }
        let unpacked = part.join("unpacked")
        Directory.create(unpacked)
        if (!host.unpack(archive, unpacked)) {
            say("${archive}: not unpacked")
            return 1
        }
        let src = part.join("src")
        if (!layOut(unpacked, src)) {
            say("${url}: no stdlib/libs/std in it")
            return 1
        }
        File.writeTo(src.join(SRC_STAMP), "${commit}\n".toArray())
        removeIfExists(dir, recursive: true)
        rename(src, to: dir)
        say("${dir}: std's sources of ${version}, cangjie_runtime ${commit}")
        0
    } catch (e: FSException) {
        say("${dir}: not written: ${e.message}")
        1
    } finally {
        try {
            removeIfExists(part, recursive: true)
        } catch (_: FSException) {
            ()
        }
    }
}

/**
 * The version `cjc --version` prints (`Cangjie Compiler: 1.3.0-alpha.20261002001050 (cjnative)`):
 * a nightly's is its tag.
 */
func compilerVersionOf(output: String): ?String {
    let prefix = "Cangjie Compiler: "
    for (line in output.lines() where line.startsWith(prefix)) {
        let version = line[prefix.size..].trimAscii()
        let end = version.indexOf(" ") ?? version.size
        if (end > 0) {
            return version[..end]
        }
    }
    None
}

/**
 * The commit of `cangjie_runtime` the first release notes of `version` that name one give.
 */
func runtimeCommitOfRelease(version: String, host: SrcHost): ?String {
    for (base in RELEASE_NOTES) {
        if (let Some(commit) <- host.get("${base}${version}").flatMap {notes => runtimeCommitOf(notes)}) {
            return commit
        }
    }
    None
}

/**
 * The commit of `cangjie_runtime` that release notes name, as a nightly's do: a line
 * ``- **cangjie_runtime**: `5d555bcc34d6` ``, here inside the JSON an API answers with.
 */
func runtimeCommitOf(notes: String): ?String {
    let key = "**cangjie_runtime**:"
    let at = notes.indexOf(key) ?? return None
    let rest = notes[at + key.size..].trimAsciiStart()
    if (!rest.startsWith("`")) {
        return None
    }
    let end = rest[1..].indexOf("`") ?? return None
    let commit = rest[1..1 + end]
    if (commit.size >= 7 && commit.size <= 40 && commit.toArray().all {b => isHex(b)}) {
        commit
    } else {
        None
    }
}

func isHex(b: Byte): Bool {
    (b >= b'0' && b <= b'9') || (b >= b'a' && b <= b'f')
}

/**
 * The commit `dir`'s stamp names, `None` without one.
 */
func stampOf(dir: Path): ?String {
    let stamp = dir.join(SRC_STAMP)
    try {
        if (exists(stamp)) {
            String.fromUtf8(File.readFrom(stamp)).trimAscii()
        } else {
            None
        }
    } catch (_: FSException) {
        None
    }
}

/**
 * Whether `dir` is there, not empty and not stamped: the user's, not to be replaced.
 */
func holdsOther(dir: Path): Bool {
    exists(dir) && stampOf(dir).isNone() && !(FileInfo(dir).isDirectory() && Directory.isEmpty(dir))
}

/**
 * Moves `std` and the `LICENSE` of the one directory `unpacked` holds, `cangjie_runtime` at a
 * commit, into `src`; `false` if it has no `stdlib/libs/std`.
 */
func layOut(unpacked: Path, src: Path): Bool {
    let tops = Directory.readFrom(unpacked).filter {info => info.isDirectory()}
    if (tops.size != 1) {
        return false
    }
    let top = tops[0].path
    let std = top.join("stdlib").join("libs").join("std")
    if (!exists(std)) {
        return false
    }
    Directory.create(src)
    rename(std, to: src.join("std"))
    if (exists(top.join("LICENSE"))) {
        rename(top.join("LICENSE"), to: src.join("LICENSE"))
    }
    true
}
