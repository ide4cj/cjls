package cjmcp

import std.collection.ArrayList
import std.fs.{FileInfo, Path, canonicalize, exists}
import stdx.log.Logger
import loupe.vfs.VfsPath

class WorkspaceEntry {
    WorkspaceEntry(let root: String, let id: String, let python: PythonSession) {}
}

/**
 * Owned by the sequential protocol loop. Bound polling workers and macro hosts,
 * retaining the most recently used roots without any shared active-root setting.
 */
class WorkspaceSessions {
    private let entries = ArrayList<WorkspaceEntry>()
    private var generation: Int64 = 0

    func acquire(written: String, logger: Logger): WorkspaceEntry {
        // Remove observed deletions before resolving aliases, including failed selections.
        var index = entries.size - 1
        while (index >= 0) {
            if (!exists(entries[index].root)) {
                let removed = entries[index]
                entries.remove(at: index)
                removed.python.close()
            }
            index--
        }
        if (!exists(written)) {
            throw IllegalArgumentException("workspace directory does not exist: ${written}")
        }
        let path = canonicalize(Path(written))
        if (!FileInfo(path).isDirectory()) {
            throw IllegalArgumentException("workspace root must be a directory: ${written}")
        }
        let root = path.toString()
        for (i in 0..entries.size) {
            if (entries[i].root == root) {
                let entry = entries[i]
                entries.remove(at: i)
                entries.add(entry)
                return entry
            }
        }
        if (entries.size == 4) {
            let removed = entries[0]
            entries.remove(at: 0)
            removed.python.close()
        }
        generation++
        let id = generation.toString()
        let entry = WorkspaceEntry(
            root,
            id,
            PythonSession(VfsPath.file(root), logger: logger, sessionId: id)
        )
        entries.add(entry)
        entry
    }

    func close(): Unit {
        if (entries.isEmpty()) {
            return
        }
        let entry = entries[entries.size - 1]
        entries.remove(at: entries.size - 1)
        // Cleanup failures must still release every remaining worker and macro host.
        try {
            entry.python.close()
        } finally {
            close()
        }
    }
}
