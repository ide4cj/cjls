package loupe.vfs

import std.collection.*
import std.deriving.*
import std.fs.*
import std.time.DateTime
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
 * What tells a file read before from one changed since without reading it: its size and the time it
 * was last written.
 */
@Derive[Equatable]
public struct FileStamp {
    public FileStamp(public let size: Int64, public let modified: DateTime) {}
}

/**
 * The stamp of the file at `path`, `None` if it is not there, is no regular file, or for a virtual
 * path.
 */
public func fileStamp(path: VfsPath): ?FileStamp {
    let filePath = path.filePath ?? return None
    try {
        let info = FileInfo(filePath)
        if (info.isRegular()) {
            FileStamp(info.size, info.lastModificationTime)
        } else {
            None
        }
    } catch (_: FSException) {
        None
    }
}

/**
 * A file `readBinaries` read, or found unchanged.
 */
public struct BinaryRead {
    public BinaryRead(
        public let path: VfsPath,
        public let stamp: FileStamp,
        /**
         * What it holds, `None` if its stamp is the one it was known by: unchanged, it is not read.
         */
        public let bytes: ?Array<Byte>
    ) {}
}

/**
 * What `readBinaries` read, and whether that is all of them.
 */
public struct BinariesRead {
    public BinariesRead(
        public let files: Array<BinaryRead>,
        /**
         * The bytes the files take, those unchanged too: what is left of the budget is for the text.
         */
        public let size: Int64,
        /**
         * Whether files were left out for the budget.
         */
        public let truncated: Bool
    ) {}
}

/**
 * The files at `paths`, as bytes: one whose stamp is what `known` gives for it is not read again, one
 * that is not there or cannot be read is left out, and so is one that does not fit in what is left of
 * `budget`, unchanged or not, in the order of `paths`.
 *
 * Touches nothing but the disk and `known`.
 */
public func readBinaries(paths: Array<VfsPath>, known!: (VfsPath) -> ?FileStamp, budget!: Int64 = Int64.Max): BinariesRead {
    let files = ArrayList<BinaryRead>()
    var left = budget
    var truncated = false
    for (path in paths) {
        let stamp = fileStamp(path) ?? continue
        if (stamp.size > left) {
            truncated = true
            continue
        }
        if (known(path) == Some(stamp)) {
            files.add(BinaryRead(path, stamp, None))
        } else {
            let bytes = try {
                File.readFrom(path.filePath.getOrThrow())
            } catch (_: FSException) {
                continue
            }
            files.add(BinaryRead(path, stamp, bytes))
        }
        left -= stamp.size
    }
    BinariesRead(files.toArray(), budget - left, truncated)
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
