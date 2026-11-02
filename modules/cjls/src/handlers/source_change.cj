package cjls.handlers

import std.collection.ArrayList
import cjls.lsp_types.*
import cjls.lsp_types.Range as LspRange
import loupe.vfs.VfsPath
import rope.{Encoding, Rope}
import source_change.{FileChange, SourceChange, validatedEdits}
import stdxx.Nullable

/**
 * Translates a change prepared from the request snapshot to LSP documentChanges.
 * Paths are absolute filesystem paths; versionOf reads open-document versions from that snapshot.
 * The caller must require documentChanges support; resourceOperations is the client's advertised list.
 * File operations never overwrite or ignore existing/missing files.
 *
 * @throws IllegalArgumentException - for invalid changes or unsupported resource operations
 */
func sourceChangeEdit(
    change: SourceChange,
    encoding: Encoding,
    versionOf: (String) -> ?Int32,
    resourceOperations: Array<String>
): WorkspaceEdit {
    change.validate()
    let changes = ArrayList<TextDocumentEditOrCreateFileOrRenameFileOrDeleteFile>()
    for (file in change.files) {
        match (file) {
            case FileChange.EditFile(path, before, edits) =>
                let uri = VfsPath.file(path).toUri()
                let version =
                    match (versionOf(path)) {
                        case Some(value) => Nullable<Int32>.Value(value)
                        case None => Nullable<Int32>.Null
                    }
                let text = Rope(before)
                changes.add(
                    TextDocumentEditOrCreateFileOrRenameFileOrDeleteFile.AsTextDocumentEdit(
                        TextDocumentEdit(
                            textDocument: OptionalVersionedTextDocumentIdentifier(
                                uri: uri,
                                version: version
                            ),
                            edits: validatedEdits(before, edits)
                                .map {
                                    edit =>
                                    TextEditOrAnnotatedTextEditOrSnippetTextEdit.AsTextEdit(
                                        textEdit(text, edit, encoding)
                                    )
                                }
                        )
                    )
                )
            case FileChange.CreateFile(path, text) =>
                requireResourceOperation(resourceOperations, "create")
                let uri = VfsPath.file(path).toUri()
                changes.add(
                    TextDocumentEditOrCreateFileOrRenameFileOrDeleteFile.AsCreateFile(
                        CreateFile(uri: uri)
                    )
                )
                let start = Position(line: 0, character: 0)
                changes.add(
                    TextDocumentEditOrCreateFileOrRenameFileOrDeleteFile.AsTextDocumentEdit(
                        TextDocumentEdit(
                            textDocument: OptionalVersionedTextDocumentIdentifier(
                                uri: uri,
                                version: Nullable.Null
                            ),
                            edits: [
                                TextEditOrAnnotatedTextEditOrSnippetTextEdit.AsTextEdit(
                                    TextEdit(
                                        range: LspRange(start: start, end: start),
                                        newText: text
                                    )
                                )
                            ]
                        )
                    )
                )
            case FileChange.RenameFile(path, target, _) =>
                requireResourceOperation(resourceOperations, "rename")
                changes.add(
                    TextDocumentEditOrCreateFileOrRenameFileOrDeleteFile.AsRenameFile(
                        RenameFile(
                            oldUri: VfsPath.file(path).toUri(),
                            newUri: VfsPath.file(target).toUri()
                        )
                    )
                )
            case FileChange.DeleteFile(path, _) =>
                requireResourceOperation(resourceOperations, "delete")
                changes.add(
                    TextDocumentEditOrCreateFileOrRenameFileOrDeleteFile.AsDeleteFile(
                        DeleteFile(uri: VfsPath.file(path).toUri())
                    )
                )
        }
    }
    WorkspaceEdit(documentChanges: changes.toArray())
}

private func requireResourceOperation(supported: Array<String>, operation: String): Unit {
    if (!supported.contains(operation)) {
        throw IllegalArgumentException("client does not support ${operation} resource operations")
    }
}
