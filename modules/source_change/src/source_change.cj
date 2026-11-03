package source_change

import std.collection.HashSet
import std.deriving.Derive

/**
 * A file operation. Existing-file operations carry the complete expected original text.
 * Paths use the consumer's normalized namespace; renames never overwrite a destination.
 * CreateFile includes initial contents, so it needs no subsequent EditFile.
 */
@Derive[Equatable, ToString]
public enum FileChange {
    EditFile(String, String, Array<TextEdit>)
    | CreateFile(String, String)
    | RenameFile(String, String, String)
    | DeleteFile(String, String)

    /**
     * Every path reserved by this operation, including a rename destination.
     */
    public func paths(): Array<String> {
        match (this) {
            case EditFile(path, _, _) => [path]
            case CreateFile(path, _) => [path]
            case RenameFile(path, target, _) => [path, target]
            case DeleteFile(path, _) => [path]
        }
    }
}

/**
 * A collection of independent file operations, not a filesystem transaction.
 * Each path may occur once, including rename destinations: rename chains and an edit
 * of a renamed/created file must be composed by the producer before constructing it.
 * Consumers resolve paths, check expected contents and capabilities, and own application.
 */
@Derive[Equatable, ToString]
public struct SourceChange {
    public SourceChange(public let files: Array<FileChange>) {}

    /**
     * Checks path spelling conflicts and all text edits without touching the filesystem.
     * Consumers must also reject aliases after resolving paths in their own namespace.
     *
     * @throws IllegalArgumentException - for empty or repeated paths, or invalid text edits
     */
    public func validate(): Unit {
        let used = HashSet<String>()
        for (file in files) {
            for (path in file.paths()) {
                if (path.isEmpty() || !used.add(path)) {
                    throw IllegalArgumentException("empty or repeated source change path: ${path}")
                }
            }
            if (let EditFile(_, before, edits) <- file) {
                applyEdits(before, edits)
            }
        }
    }
}
