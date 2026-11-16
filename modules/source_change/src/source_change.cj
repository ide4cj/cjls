package source_change

import std.collection.HashSet
import py_interop.*
import py_interop.internal_macros.DerivePython

/**
 * A file operation. Existing-file operations carry the complete expected original text.
 * Paths use the consumer's normalized namespace; renames never overwrite a destination.
 * CreateFile includes initial contents, so it needs no subsequent EditFile.
 */
@DerivePython
@PyDoc["A file operation. Existing-file operations carry the complete expected original text. Paths use the consumer's normalized namespace; renames never overwrite a destination. CreateFile includes initial contents, so it needs no subsequent EditFile."]
public enum FileChange <: Equatable<FileChange> & ToString {
    EditFile(String, String, Array<TextEdit>)
    | CreateFile(String, String)
    | RenameFile(String, String, String)
    | DeleteFile(String, String)

    public operator func ==(other: FileChange): Bool {
        match ((this, other)) {
            case (EditFile(a, b, c), EditFile(x, y, z)) => a == x && b == y && c == z
            case (CreateFile(a, b), CreateFile(x, y)) => a == x && b == y
            case (RenameFile(a, b, c), RenameFile(x, y, z)) => a == x && b == y && c == z
            case (DeleteFile(a, b), DeleteFile(x, y)) => a == x && b == y
            case _ => false
        }
    }

    public operator func !=(other: FileChange): Bool {
        !(this == other)
    }

    public func toString(): String {
        match (this) {
            case EditFile(path, _, edits) => "EditFile(${path}, ${edits.size} edits)"
            case CreateFile(path, _) => "CreateFile(${path})"
            case RenameFile(path, target, _) => "RenameFile(${path}, ${target})"
            case DeleteFile(path, _) => "DeleteFile(${path})"
        }
    }

    /**
     * Every path reserved by this operation, including a rename destination.
     */
    @PyDoc["Every path reserved by this operation, including a rename destination."]
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
@DerivePython
@PyDoc["A collection of independent file operations, not a filesystem transaction. Each path may occur once, including rename destinations: rename chains and an edit of a renamed/created file must be composed by the producer before constructing it. Consumers resolve paths, check expected contents and capabilities, and own application."]
public struct SourceChange <: Equatable<SourceChange> & ToString {
    public SourceChange(public let files: Array<FileChange>) {}

    public operator func ==(other: SourceChange): Bool {
        files == other.files
    }

    public operator func !=(other: SourceChange): Bool {
        !(this == other)
    }

    public func toString(): String {
        "SourceChange(${files})"
    }

    /**
     * Checks path spelling conflicts and all text edits without touching the filesystem.
     * Consumers must also reject aliases after resolving paths in their own namespace.
     *
     * @throws IllegalArgumentException - for empty or repeated paths, or invalid text edits
     */
    @PyDoc["Checks path spelling conflicts and all text edits without touching the filesystem. Consumers must also reject aliases after resolving paths in their own namespace.  @throws IllegalArgumentException - for empty or repeated paths, or invalid text edits"]
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
