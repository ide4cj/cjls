package cjmcp

import std.collection.{ArrayList, HashSet}
import std.fs.{Directory, File, FileInfo, HardLink, Path, exists, remove}
import loupe.vfs.VfsPath
import source_change.{FileChange, SourceChange, applyEdits}
@When[os == "Linux"]
import py_interop.*
@When[os == "Linux"]
import py_interop.internal_macros.DerivePython

/**
 * Application report using zero-based operation indices in the supplied SourceChange.
 * Preflight failures have no applied operations and no failed index. An I/O failure
 * stops at failed; that operation may have changed disk. Nothing is rolled back.
 * revision remains the script's original analysis revision, including after success.
 */
@When[os == "Linux"]
@DerivePython
struct ApplyChangeResult {
    ApplyChangeResult(
        public let revision: Int64,
        public let applied: Array<Int64>,
        public let failed: ?Int64,
        public let error: ?String
    ) {}

    public prop isSuccess: Bool {
        get() {
            error.isNone()
        }
    }
}

/**
 * Validates the entire change before touching disk, then applies independent operations in order.
 *
 * @throws IllegalStateException - if revision differs from the script's analysis revision
 */
@When[os == "Linux"]
func applySourceChange(
    state: WorkspaceState,
    change: SourceChange,
    revision: Int64
): ApplyChangeResult {
    if (revision != state.revision) {
        throw IllegalStateException(
            "ContentModified: source change revision does not match the workspace"
        )
    }
    let files =
        try {
            prepareSourceChange(state, change)
        } catch (e: Exception) {
            return ApplyChangeResult(revision, [], None, Some(e.message))
        } catch (e: Error) {
            return ApplyChangeResult(revision, [], None, Some(e.message))
        }
    applyPreparedSourceChange(files, revision, applyFileChange)
}

@When[os == "Linux"]
func applyPreparedSourceChange(
    files: Array<FileChange>,
    revision: Int64,
    apply: (FileChange) -> Unit
): ApplyChangeResult {
    let applied = ArrayList<Int64>()
    for (i in 0..files.size) {
        try {
            apply(files[i])
            applied.add(i)
        } catch (e: Exception) {
            return ApplyChangeResult(revision, applied.toArray(), Some(i), Some(e.message))
        } catch (e: Error) {
            return ApplyChangeResult(revision, applied.toArray(), Some(i), Some(e.message))
        }
    }
    ApplyChangeResult(revision, applied.toArray(), None, None)
}

@When[os == "Linux"]
private func prepareSourceChange(state: WorkspaceState, change: SourceChange): Array<FileChange> {
    change.validate()
    let root = Path(state.root.toString()).normalize()
    let files = change.files.map { file => normalizedFileChange(root, file) }
    // Different spellings can refer to one path; shared validation sees only the supplied namespace.
    SourceChange(files).validate()
    let paths = HashSet<String>()
    for (file in files) {
        paths.add(all: file.paths())
    }
    for (file in files) {
        for (path in file.paths()) {
            var parent = Path(path).parent
            while (parent != root) {
                if (paths.contains(parent.toString())) {
                    throw IllegalArgumentException(
                        "a changed file is also used as a parent directory: ${parent}"
                    )
                }
                parent = parent.parent
            }
        }
        match (file) {
            case FileChange.EditFile(path, before, _) => checkOriginal(state, path, before)
            case FileChange.CreateFile(path, _) => requireMissing(path)
            case FileChange.RenameFile(path, target, before) =>
                checkOriginal(state, path, before)
                requireMissing(target)
            case FileChange.DeleteFile(path, before) => checkOriginal(state, path, before)
        }
        for (path in file.paths()) {
            checkParent(Path(path).parent)
        }
    }
    files
}

@When[os == "Linux"]
private func normalizedFileChange(root: Path, file: FileChange): FileChange {
    match (file) {
        case FileChange.EditFile(path, before, edits) =>
            FileChange.EditFile(changePath(root, path), before, edits)
        case FileChange.CreateFile(path, text) =>
            FileChange.CreateFile(changePath(root, path), text)
        case FileChange.RenameFile(path, target, before) =>
            FileChange.RenameFile(changePath(root, path), changePath(root, target), before)
        case FileChange.DeleteFile(path, before) =>
            FileChange.DeleteFile(changePath(root, path), before)
    }
}

@When[os == "Linux"]
private func changePath(root: Path, written: String): String {
    let raw = Path(written)
    let path = (if (raw.isAbsolute()) { raw } else { root.join(raw) }).normalize()
    let prefix =
        if (root.toString().endsWith(Path.Separator)) {
            root.toString()
        } else {
            "${root}${Path.Separator}"
        }
    if (!path.toString().startsWith(prefix) || path == root) {
        throw IllegalArgumentException("source change path is outside the workspace: ${written}")
    }
    var ancestor = path
    while (ancestor != root) {
        if (exists(ancestor) && FileInfo(ancestor).isSymbolicLink()) {
            throw IllegalArgumentException(
                "source change paths must not traverse symbolic links: ${written}"
            )
        }
        ancestor = ancestor.parent
    }
    path.toString()
}

@When[os == "Linux"]
private func checkParent(path: Path): Unit {
    if (exists(path)) {
        if (!FileInfo(path).isDirectory()) {
            throw IllegalArgumentException("source change parent is not a directory: ${path}")
        }
    } else {
        checkParent(path.parent)
    }
}

@When[os == "Linux"]
private func checkOriginal(state: WorkspaceState, path: String, before: String): Unit {
    checkDiskOriginal(path, before)
    if (let Some(id) <- state.vfs.fileId(VfsPath.file(path))) {
        let text = state.vfs.fileContents(id).getOrThrow().toString()
        if (text != before) {
            throw IllegalStateException(
                "ContentModified: expected text differs from the analysis revision: ${path}"
            )
        }
    }
}

@When[os == "Linux"]
private func checkDiskOriginal(path: String, before: String): Unit {
    if (!FileInfo(path).isRegular() || File.readFrom(path) != before.toArray()) {
        throw IllegalStateException("ContentModified: file differs from expected text: ${path}")
    }
}

@When[os == "Linux"]
private func requireMissing(path: String): Unit {
    if (exists(path)) {
        throw IllegalStateException("source change destination already exists: ${path}")
    }
}

@When[os == "Linux"]
private func ensureParent(path: String): Unit {
    let parent = Path(path).parent
    if (!exists(parent)) {
        Directory.create(parent, recursive: true)
    }
}

@When[os == "Linux"]
private func applyFileChange(file: FileChange): Unit {
    match (file) {
        case FileChange.EditFile(path, before, edits) =>
            let after = applyEdits(before, edits)
            checkDiskOriginal(path, before)
            // Keep existing file permissions and identity, as ordinary editor writes do.
            File.writeTo(path, after.toArray())
        case FileChange.CreateFile(path, text) =>
            ensureParent(path)
            let temporary = File.createTemp(Path(path).parent)
            let staging = temporary.info.path
            try {
                temporary.write(text.toArray())
                temporary.close()
                // Link creation fails atomically when the destination exists; File.create is check-then-truncate.
                HardLink.create(path, to: staging.toString())
            } finally {
                temporary.close()
                remove(staging)
            }
        case FileChange.RenameFile(path, target, before) =>
            ensureParent(target)
            checkDiskOriginal(path, before)
            // Reserve the destination without overwriting a concurrently created file.
            HardLink.create(target, to: path)
            remove(path)
        case FileChange.DeleteFile(path, before) =>
            checkDiskOriginal(path, before)
            remove(path)
    }
}
