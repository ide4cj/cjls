package loupe.vfs

import std.collection.*
import std.fs.*
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

    private func readSourceFile(path: VfsPath): Unit {
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
