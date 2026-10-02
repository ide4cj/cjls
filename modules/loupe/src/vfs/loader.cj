package loupe.vfs

import std.collection.*
import std.deriving.*
import std.fs.*
import std.sort.*
import std.time.DateTime
import cjo.{CjoException, openCjo}
import rope.Rope

/**
 * What `readRoots` read: the files, and whether that is all of them.
 */
public struct RootsRead {
    public RootsRead(
        public let files: Array<(VfsPath, Rope)>,
        /**
         * Whether files were left out for the budget.
         */
        public let truncated: Bool
    ) {}
}

/**
 * The Cangjie files under `roots`, as the disk holds them: every `*.cj`, but for those in a
 * `target` directory (cjpm's output) or a hidden one (named with a leading `.`). Symbolic links are
 * not followed, so the walk cannot cycle; a file that cannot be read, or is not UTF-8, is left out,
 * and so is a directory that cannot be listed. A root inside another is read once, and a virtual
 * one not at all. At most `budget` bytes are kept, as a root far wider than a project (a home
 * directory) would take all the memory there is: a file that does not fit in what is left is left
 * out, and the walk goes on for those that do.
 *
 * Touches nothing but the disk, so any thread may call it.
 */
public func readRoots(roots: Array<VfsPath>, budget!: Int64 = Int64.Max): RootsRead {
    let walk = Walk(budget)
    for (root in outermost(roots)) {
        if (let Some(dir) <- root.filePath) {
            walk.readDirectory(dir)
        }
    }
    RootsRead(walk.files.toArray(), walk.truncated)
}

/**
 * The files at `paths`, as `readRoots` reads them: one that is not there, cannot be read, or is
 * not UTF-8 is left out, and so is one that does not fit in what is left of `budget`.
 */
public func readFiles(paths: Array<VfsPath>, budget!: Int64 = Int64.Max): RootsRead {
    let walk = Walk(budget)
    for (path in paths) {
        walk.readSourceFile(path)
    }
    RootsRead(walk.files.toArray(), walk.truncated)
}

/**
 * What the file at `path` holds on disk, `None` if it is not there, cannot be read, or is not
 * UTF-8, and for a virtual path.
 */
public func readFile(path: VfsPath): ?Rope {
    let filePath = path.filePath ?? return None
    try {
        Rope(String.fromUtf8(File.readFrom(filePath)))
    } catch (_: FSException) {
        None
    } catch (_: IllegalArgumentException) {
        None
    }
}

/**
 * Whether `readRoots(roots)` reads the file at `path`, were it on the disk: whether a change the
 * editor reports is one to a file of the workspace.
 */
public func isWorkspaceFile(path: VfsPath, roots: Array<VfsPath>): Bool {
    isCangjieFile(path.toString()) && roots.iterator().any {
        root => match (path.segmentsUnder(root)) {
            case Some(segments) where segments.size > 0 =>
                segments[..segments.size - 1].iterator().all {name => isScanned(name)}
            case _ => false
        }
    }
}

/**
 * Whether the walk goes into the directory `name`: neither cjpm's output nor a hidden one.
 */
public func isScanned(name: String): Bool {
    name != "target" && !name.startsWith(".")
}

public func isCangjieFile(name: String): Bool {
    name.endsWith(".cj")
}

/**
 * The files read so far, and the bytes left to keep.
 */
private class Walk {
    let files = ArrayList<(VfsPath, Rope)>()
    var truncated = false

    Walk(private var budget: Int64) {}

    func readDirectory(dir: Path): Unit {
        let entries = try {
            Directory.readFrom(dir)
        } catch (_: FSException) {
            return
        }
        for (entry in entries where !entry.isSymbolicLink()) {
            if (entry.isDirectory()) {
                if (isScanned(entry.name)) {
                    readDirectory(entry.path)
                }
            } else if (entry.isRegular() && isCangjieFile(entry.name)) {
                // told by its size, so a file that cannot fit is not even read
                if (entry.size > budget) {
                    truncated = true
                } else {
                    readSourceFile(VfsPath.file(entry.path))
                }
            }
        }
    }

    func readSourceFile(path: VfsPath): Unit {
        let text = readFile(path) ?? return ()
        if (text.size > budget) {
            truncated = true
            return
        }
        budget -= text.size
        files.add((path, text))
    }
}

/**
 * `roots` without those inside another one, and without repeats.
 */
private func outermost(roots: Array<VfsPath>): Array<VfsPath> {
    let kept = ArrayList<VfsPath>()
    for (root in roots) {
        let inside = roots.iterator().any {other => other != root && root.isUnder(other)}
        if (!inside && !kept.contains(root)) {
            kept.add(root)
        }
    }
    kept.toArray()
}

let CJO_SUFFIX = ".cjo"

/**
 * What tells a file changed without reading it: its size, and when it was written last.
 */
@Derive[Equatable]
public struct FileStamp {
    public FileStamp(public let size: Int64, public let modified: DateTime) {}
}

/**
 * The `.cjo` of a package compiled already: the binary it is of (`std`, one of `bin-dependencies`),
 * the package, and where the file is.
 */
@Derive[Equatable, Hashable]
public struct CjoFile {
    public CjoFile(public let binary: String, public let name: String, public let path: VfsPath) {}
}

/**
 * A `.cjo` read, and its stamp then; `bytes` are `None` for one unchanged, which is not read again.
 */
public struct CjoFileRead {
    public CjoFileRead(public let file: CjoFile, public let stamp: FileStamp, public let bytes: ?Array<Byte>) {}
}

/**
 * What `readCjoFiles` read: the files, the bytes they take, and why others were left out.
 */
public struct CjoRead {
    public CjoRead(
        public let files: Array<CjoFileRead>,
        /**
         * The bytes of the files kept, read now or before.
         */
        public let size: Int64,
        /**
         * Each file left out for being no `.cjo` this reader knows, with the reason.
         */
        public let problems: Array<String>,
        /**
         * Whether files were left out for the budget.
         */
        public let truncated: Bool
    ) {}
}

/**
 * The `.cjo` in the directory `dir`, each a package of `binary` named as its file is
 * (`std.core.cjo` is `std.core`), in the order of their names; none for a directory that cannot be
 * listed, or a virtual one.
 */
public func cjoFilesIn(binary: String, dir: VfsPath): Array<CjoFile> {
    let path = dir.filePath ?? return []
    let entries = try {
        Directory.readFrom(path)
    } catch (_: FSException) {
        return []
    }
    let files = entries.filter {entry => entry.isRegular() && entry.name.endsWith(CJO_SUFFIX)}.map {
        entry => CjoFile(binary, entry.name.removeSuffix(CJO_SUFFIX), VfsPath.file(entry.path))
    }
    sort(files, by: {a, b => a.name.compare(b.name)})
    files
}

/**
 * Reads `files`, each path once, but for those whose stamp `unchanged` takes: they are kept as
 * they were, and not read. A file that is not there or cannot be read is left out, and so is one
 * that is not a `.cjo` of the format this reader knows, with a problem; so is one that does not
 * fit in what is left of `budget`, a file kept unread taking its size of it as one read does.
 *
 * Touches nothing but the disk, so any thread may call it.
 */
public func readCjoFiles(files: Array<CjoFile>, unchanged!: (CjoFile, FileStamp) -> Bool = {_, _ => false},
    budget!: Int64 = Int64.Max): CjoRead {
    let read = ArrayList<CjoFileRead>()
    let problems = ArrayList<String>()
    let seen = HashSet<VfsPath>()
    var left = budget
    var truncated = false
    for (file in files where seen.add(file.path)) {
        let path = file.path.filePath ?? continue
        let stamp = try {
            let info = FileInfo(path)
            FileStamp(info.size, info.lastModificationTime)
        } catch (_: FSException) {
            continue
        }
        if (stamp.size > left) {
            truncated = true
            continue
        }
        if (unchanged(file, stamp)) {
            left -= stamp.size
            read.add(CjoFileRead(file, stamp, None))
            continue
        }
        let bytes = try {
            File.readFrom(path)
        } catch (_: FSException) {
            continue
        }
        if (let Some(problem) <- cjoProblem(bytes)) {
            problems.add("${file.path}: ${problem}, left out")
            continue
        }
        left -= bytes.size
        read.add(CjoFileRead(file, stamp, bytes))
    }
    CjoRead(read.toArray(), budget - left, problems.toArray(), truncated)
}

/**
 * Why `bytes` are no `.cjo` this reader knows, `None` if they are one: only the header is checked,
 * the rest is read when it is asked for.
 */
func cjoProblem(bytes: Array<Byte>): ?String {
    try {
        openCjo(bytes)
        None
    } catch (e: CjoException) {
        e.message
    }
}
