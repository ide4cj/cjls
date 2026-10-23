package cjls.server

import std.collection.HashSet
import std.convert.Parsable
import std.fs.{Directory, exists, File, FileInfo, FSException, OpenMode, Path, remove}
import std.sync.Mutex
import std.time.DateTime
import loupe.vfs.VfsPath
import macro_host.{LOCK_FILE, tryLockCacheDir}
import platform.userCacheDir
import project_model.projectDirOf

// The directory the server writes, of its own, beside a project (D106, #333): `<project>/.cache/cjls`, as clangd
// keeps `.cache/clangd`, else one of the user's cache directory. What is in it is the server's alone, made again
// whenever it is missing.

/**
 * The number of the directory's layout: a directory that holds another, or none, is emptied first.
 */
const CACHE_LAYOUT = "1"

/**
 * The macro packages the server builds, one directory per compiler (D104).
 */
public const MACRO_BUILD_DIR = "macro-build"

/**
 * The expanded files the server shows (D103).
 */
public const EXPANDED_DIR = "expanded"

/**
 * What ends an expanded file's name, after its source file's, as cjc's `--debug-macro` names one.
 */
public const EXPANDED_SUFFIX = ".macrocall"

/**
 * In `macro-build/<version>`: when it was last used, in Unix seconds.
 */
const USED_FILE = ".used"

/**
 * In a directory of the user's cache: the project directory it stands for.
 */
const BASE_FILE = "BASE"

/**
 * A `macro-build/<version>` unused for longer is removed when its cache directory is opened.
 */
let MACRO_BUILD_KEPT = Duration.day * 7

/**
 * The cache directory tag (https://bford.info/cachedir/), which backup tools skip.
 */
const CACHEDIR_TAG =
    "Signature: 8a477f597d28d172789f06886806bc55\n# This file is a cache directory tag created by cjls.\n# For information about cache directory tags see https://bford.info/cachedir/\n"

/**
 * The cache directories of one server: each opened once in its process, which empties its `expanded/` and removes
 * what of `macro-build/` went unused. Safe to share between threads.
 */
public class CacheDirs {
    private let opened = HashSet<String>()
    private let mutex = Mutex()

    /**
     * @param env - the environment, which names the user's cache directory
     * @param now - the time, which says how long a `macro-build/<version>` went unused
     */
    public CacheDirs(
        private let env: (String) -> ?String,
        private let now!: () -> DateTime = { => DateTime.now() }
    ) {}

    /**
     * The cache directory of the file at `path`, that of its project (`cacheBaseOf`); `None` for a virtual path, or
     * if none can be written, neither in the project nor in the user's cache.
     */
    public func of(path: VfsPath, roots: Array<VfsPath>): ?CacheDir {
        open(cacheBaseOf(path, roots, env) ?? return None)
    }

    /**
     * The cache directory of the project directory `base`: `<base>/.cache/cjls`, else, if that cannot be written,
     * `<user cache>/cjls/<name>-<hash>`. It is made, and set in order the first time this process opens it.
     */
    public func open(base: VfsPath): ?CacheDir {
        let basePath = base.filePath ?? return None
        let inProject = basePath.join(".cache").join("cjls")
        if (prepare(inProject, base, inUserCache: false)) {
            return CacheDir(base, inProject)
        }
        let user = userCacheDir(env) ?? return None
        let fallback = user.join("cjls").join(userCacheEntryOf(base))
        if (prepare(fallback, base, inUserCache: true)) {
            return CacheDir(base, fallback)
        }
        None
    }

    private func prepare(dir: Path, base: VfsPath, inUserCache!: Bool): Bool {
        synchronized (mutex) {
            try {
                ensureDir(dir)
                let layout = dir.join("LAYOUT")
                if (!(exists(layout) && String.fromUtf8(File.readFrom(layout)) == CACHE_LAYOUT)) {
                    emptyDir(dir)
                    File.writeTo(layout, CACHE_LAYOUT.toArray())
                }
                writeIfMissing(dir.join(".gitignore"), "*\n")
                writeIfMissing(dir.join("CACHEDIR.TAG"), CACHEDIR_TAG)
                if (inUserCache) {
                    File.writeTo(dir.join(BASE_FILE), base.toString().toArray())
                }
                if (opened.add(dir.toString())) {
                    removeTree(dir.join(EXPANDED_DIR))
                    pruneMacroBuilds(dir.join(MACRO_BUILD_DIR), now())
                }
                true
            } catch (_: FSException) {
                false
            }
        }
    }
}

/**
 * The server's directory of one project (`CacheDirs.open`).
 */
public class CacheDir {
    CacheDir(
        /**
         * The project directory it is of: an expanded file's path under `expanded/` is its source's under this.
         */
        public let base: VfsPath,
        /**
         * Where it is: `<base>/.cache/cjls`, or a directory of the user's cache.
         */
        public let path: Path
    ) {}

    /**
     * The directory the macro packages are built into by the compiler `name` (a directory's name, no separator), made
     * and marked used now, so that it outlives `MACRO_BUILD_KEPT`.
     *
     * @throws FSException - if it cannot be made
     * @throws IllegalArgumentException - if `name` is no directory's name
     */
    public func macroBuild(name: String, now!: DateTime = DateTime.now()): Path {
        if (
            name.isEmpty() || name == "." || name == ".." || name.contains("/") ||
                name.contains("\\")
        ) {
            throw IllegalArgumentException("not a directory's name: ${name}")
        }
        let dir = path.join(MACRO_BUILD_DIR).join(name)
        ensureDir(dir)
        File.writeTo(dir.join(USED_FILE), "${now.toUnixTimeStamp().toSeconds()}".toArray())
        dir
    }

    /**
     * The expanded file of the source file at `source`, `expanded/<source under base>.macrocall`; `None` if `source`
     * is not under `base`.
     */
    public func expandedFileOf(source: VfsPath): ?VfsPath {
        let segments = source.segmentsUnder(base) ?? return None
        if (segments.isEmpty()) {
            return None
        }
        var at = VfsPath.file(path.join(EXPANDED_DIR))
        for (i in 0..segments.size) {
            at =
                at
                    .join(
                        if (i == segments.size - 1) {
                            segments[i] + EXPANDED_SUFFIX
                        } else {
                            segments[i]
                        }
                    )
        }
        at
    }
}

/**
 * The project directory whose cache directory holds the file at `path`: that of the project it is of
 * (`projectDirOf`, a `cjpm.toml` workspace or a `cj-project.json`) up to the innermost of `roots` it is under, else
 * that root; up to the top of the file system under no root, else its own directory. `None` for a virtual path.
 */
public func cacheBaseOf(path: VfsPath, roots: Array<VfsPath>, env: (String) -> ?String): ?VfsPath {
    if (path.filePath.isNone()) {
        return None
    }
    var root: ?VfsPath = None
    for (one in roots where path.isUnder(one) && one != path) {
        if (root.map { it => it.toString().size < one.toString().size } ?? true) {
            root = one
        }
    }
    match (root) {
        case Some(dir) => projectDirOf(path, dir, env: env) ?? dir
        case None =>
            let top = topOf(path)
            projectDirOf(path, top, env: env) ?? path.parent
    }
}

private func topOf(path: VfsPath): VfsPath {
    var top = path
    while (let Some(up) <- top.parent) {
        top = up
    }
    top
}

/**
 * The source file the file at `path` is the expanded file of (`CacheDir.expandedFileOf`), `None` if it is none's:
 * one whose name ends with `.macrocall`, under `expanded/` of a cache directory, the innermost.
 */
public func sourceOfExpanded(path: VfsPath): ?VfsPath {
    // the text first: a cheap test for every file a snapshot lists
    if (!path.toString().endsWith(EXPANDED_SUFFIX) || path.name.size == EXPANDED_SUFFIX.size) {
        return None
    }
    var dir = path.parent
    while (let Some(at) <- dir) {
        if (
            at.name == EXPANDED_DIR && let Some(cache) <- at.parent &&
                let Some(base) <- baseOfCacheDir(cache)
        ) {
            let segments = path.segmentsUnder(at) ?? return None
            let last = segments[segments.size - 1]
            let names = segments[..segments.size - 1]
            return names
                .iterator()
                .fold(base) { one, name => one.join(name) }
                .join(last[..last.size - EXPANDED_SUFFIX.size])
        }
        dir = at.parent
    }
    None
}

/**
 * Whether the file at `path` is an expanded file (`sourceOfExpanded`): one the server writes, never a file of the
 * workspace.
 */
public func isExpandedFile(path: VfsPath): Bool {
    sourceOfExpanded(path).isSome()
}

/**
 * The project directory of the cache directory at `dir`: its parent's parent for `<base>/.cache/cjls`; what its
 * `BASE` says for one of the user's cache, which has `LAYOUT` beside it.
 */
private func baseOfCacheDir(dir: VfsPath): ?VfsPath {
    if (dir.name == "cjls" && let Some(cache) <- dir.parent && cache.name == ".cache") {
        return cache.parent
    }
    let dirPath = dir.filePath ?? return None
    try {
        if (exists(dirPath.join("LAYOUT")) && exists(dirPath.join(BASE_FILE))) {
            return VfsPath.file(String.fromUtf8(File.readFrom(dirPath.join(BASE_FILE))))
        }
    } catch (_: FSException) {
        ()
    }
    None
}

/**
 * The name of `base`'s directory in the user's cache: its own name and the hash of its path, which tells two
 * directories of one name apart.
 */
func userCacheEntryOf(base: VfsPath): String {
    let name =
        if (base.name.isEmpty() || base.name.contains(":")) {
            "root"
        } else {
            base.name
        }
    "${name}-${hexOf(base.toString().hashCode())}"
}

@OverflowWrapping
func hexOf(value: Int64): String {
    let digits = "0123456789abcdef".toArray()
    var bits = UInt64(value)
    let text = Array<Byte>(16, repeat: 0)
    for (i in 0..16) {
        text[15 - i] = digits[Int64(bits & 0xf)]
        bits = bits >> 4
    }
    String.fromUtf8(text)
}

/**
 * Removes each `<version>` of `dir` last used more than `MACRO_BUILD_KEPT` before `now`, or never, unless a build
 * holds its lock (`tryLockCacheDir`). A build that opens the lock file between its removal and the directory's goes
 * on in a directory of no lock: a week unused, then that very moment.
 */
func pruneMacroBuilds(dir: Path, now: DateTime): Unit {
    if (!exists(dir)) {
        return
    }
    for (entry in Directory.readFrom(dir) where entry.isDirectory()) {
        let used =
            try {
                Int64.parse(String.fromUtf8(File.readFrom(entry.path.join(USED_FILE))).trimAscii())
            } catch (_: Exception) {
                Int64.Min
            }
        if (now.toUnixTimeStamp().toSeconds() - used <= MACRO_BUILD_KEPT.toSeconds()) {
            continue
        }
        // under its lock, so no build is in it, then the lock file as well, which Windows keeps while it is open
        let lock = tryLockCacheDir(entry.path) ?? continue
        try {
            removeTree(entry.path, keep: LOCK_FILE)
        } finally {
            lock.close()
        }
        removeTree(entry.path)
    }
}

/**
 * Makes the directory at `path` and those above it, unless it is there: `Directory.create` throws for one that is.
 */
func ensureDir(path: Path): Unit {
    if (!exists(path)) {
        Directory.create(path, recursive: true)
    }
}

private func writeIfMissing(path: Path, text: String): Unit {
    if (!exists(path)) {
        File.writeTo(path, text.toArray())
    }
}

/**
 * Removes everything in `dir`, the directory itself kept.
 */
private func emptyDir(dir: Path): Unit {
    for (entry in Directory.readFrom(dir)) {
        removeTree(entry.path)
    }
}

/**
 * Removes the file or the directory at `path`, if there is one, a read-only file too; with `keep`, the directory
 * itself and its file of that name are left.
 */
func removeTree(path: Path, keep!: ?String = None): Unit {
    let info =
        try {
            FileInfo(path)
        } catch (_: FSException) {
            return
        }
    if (info.isDirectory() && !info.isSymbolicLink()) {
        for (entry in Directory.readFrom(path) where keep != Some(entry.name)) {
            removeTree(entry.path)
        }
        if (keep.isNone()) {
            remove(path)
        }
    } else {
        try {
            info.setWritable(true)
        } catch (_: FSException) {
            // not permitted on Windows: removed as it is
        }
        remove(path)
    }
}
