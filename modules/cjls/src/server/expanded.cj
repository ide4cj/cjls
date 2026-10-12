package cjls.server

import loupe.vfs.VfsPath

/**
 * What ends the name of an expanded file, after its source file's, as cjc's `--debug-macro` names one.
 */
public const EXPANDED_SUFFIX = ".macrocall"

/**
 * The expanded file of the source file at `source`, `<root>/.cjls/expanded/<source under root>.macrocall`, the path
 * of the source under that root, with `/`, and the directory `<root>/.cjls`: the root is the innermost of `roots` the
 * source is under, else its directory. `None` for a virtual path.
 */
public func expandedFileOf(source: VfsPath, roots: Array<VfsPath>): ?(VfsPath, String, VfsPath) {
    var root: ?VfsPath = None
    for (one in roots where source.isUnder(one) && one != source) {
        if (root.map {it => it.toString().size < one.toString().size} ?? true) {
            root = one
        }
    }
    let base = root ?? source.parent ?? return None
    let segments = source.segmentsUnder(base) ?? return None
    let relative = String.join(segments, delimiter: "/")
    let cjls = base.join(".cjls")
    let dir = cjls.join("expanded")
    let path = segments.iterator().enumerate().fold(dir) {
        at, pair => if (pair[0] == segments.size - 1) {
            at.join(pair[1] + EXPANDED_SUFFIX)
        } else {
            at.join(pair[1])
        }
    }
    (path, relative, cjls)
}

/**
 * The source file the file at `path` is the expanded file of (`expandedFileOf`), `None` if it is none's: one under a
 * directory `.cjls/expanded`, the innermost, whose name ends with `.macrocall`.
 */
public func sourceOfExpanded(path: VfsPath): ?VfsPath {
    // the text first: a cheap test for every file a snapshot lists
    if (!path.toString().endsWith(EXPANDED_SUFFIX) || path.name.size == EXPANDED_SUFFIX.size) {
        return None
    }
    var dir = path.parent
    while (let Some(at) <- dir) {
        if (at.name == "expanded" && let Some(cjls) <- at.parent && cjls.name == ".cjls" &&
            let Some(root) <- cjls.parent) {
            let segments = path.segmentsUnder(at) ?? return None
            let last = segments[segments.size - 1]
            let names = segments[..segments.size - 1]
            return names.iterator().fold(root) {one, name => one.join(name)}.join(
                last[..last.size - EXPANDED_SUFFIX.size])
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
