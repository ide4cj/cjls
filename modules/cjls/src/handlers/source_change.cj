package cjls.handlers

import std.collection.HashMap
import loupe.vfs.VfsPath
import rope.{Encoding, Rope}
import source_change.{FileChange, SourceChange, TextEdit as SourceTextEdit, validatedEdits}
import stdxx.Nullable
import cjls.lsp_types.*
import cjls.lsp_types.Range as LspRange

/**
 * Translates a change prepared from captured document text and versions to an LSP workspace edit.
 * Paths are absolute filesystem paths; versionOf supplies the corresponding open-document versions.
 * Without documentChanges support, only text edits are allowed and versions cannot be sent.
 * resourceOperations is the client's advertised list.
 * File operations never overwrite or ignore existing/missing files.
 *
 * @throws IllegalArgumentException - for invalid changes or unsupported resource operations
 */
func sourceChangeEdit(
    change: SourceChange,
    encoding: Encoding,
    versionOf: (String) -> ?Int32,
    resourceOperations: Array<String>,
    documentChanges!: Bool = true
): WorkspaceEdit {
    change.validate()
    if (!documentChanges) {
        return unversionedSourceChangeEdit(change, encoding)
    }
    let changes =
        change
            .files
            .flatMap { file => sourceFileChanges(file, encoding, versionOf, resourceOperations) }
    WorkspaceEdit(documentChanges: changes)
}

/**
 * Translates text-only changes for a client without documentChanges support.
 *
 * @throws IllegalArgumentException - if the change contains a resource operation
 */
func unversionedSourceChangeEdit(change: SourceChange, encoding: Encoding): WorkspaceEdit {
    let changes =
        change
            .files
            .map {
                file =>
                match (file) {
                    case FileChange.EditFile(path, before, edits) =>
                        (VfsPath.file(path).toUri(), sourceTextEdits(before, edits, encoding))
                    case _ =>
                        throw IllegalArgumentException(
                            "file operations require documentChanges support"
                        )
                }
            }
    WorkspaceEdit(changes: HashMap<DocumentUri, Array<TextEdit>>(changes))
}

/**
 * Translates one file operation, putting creation before its initial contents.
 *
 * @throws IllegalArgumentException - if the client does not support the resource operation
 */
func sourceFileChanges(
    file: FileChange,
    encoding: Encoding,
    versionOf: (String) -> ?Int32,
    resourceOperations: Array<String>
): Array<TextDocumentEditOrCreateFileOrRenameFileOrDeleteFile> {
    match (file) {
        case FileChange.EditFile(path, before, edits) =>
            let version =
                versionOf(path).map { value => Nullable<Int32>.Value(value) } ??
                    Nullable<Int32>.Null
            [
                sourceDocumentEdit(
                    VfsPath.file(path).toUri(),
                    version,
                    sourceTextEdits(before, edits, encoding)
                )
            ]
        case FileChange.CreateFile(path, text) =>
            requireResourceOperation(resourceOperations, "create")
            let uri = VfsPath.file(path).toUri()
            let start = Position(line: 0, character: 0)
            let edit = TextEdit(range: LspRange(start: start, end: start), newText: text)
            [
                TextDocumentEditOrCreateFileOrRenameFileOrDeleteFile.AsCreateFile(
                    CreateFile(uri: uri)
                ),
                sourceDocumentEdit(uri, Nullable.Null, [edit])
            ]
        case FileChange.RenameFile(path, target, _) =>
            requireResourceOperation(resourceOperations, "rename")
            [
                TextDocumentEditOrCreateFileOrRenameFileOrDeleteFile.AsRenameFile(
                    RenameFile(
                        oldUri: VfsPath.file(path).toUri(),
                        newUri: VfsPath.file(target).toUri()
                    )
                )
            ]
        case FileChange.DeleteFile(path, _) =>
            requireResourceOperation(resourceOperations, "delete")
            [
                TextDocumentEditOrCreateFileOrRenameFileOrDeleteFile.AsDeleteFile(
                    DeleteFile(uri: VfsPath.file(path).toUri())
                )
            ]
    }
}

/**
 * Wraps text edits with the document version captured alongside their original text.
 */
func sourceDocumentEdit(
    uri: DocumentUri,
    version: Nullable<Int32>,
    edits: Array<TextEdit>
): TextDocumentEditOrCreateFileOrRenameFileOrDeleteFile {
    let document = TextDocumentEdit(
        textDocument: OptionalVersionedTextDocumentIdentifier(uri: uri, version: version),
        edits: edits.map { edit => TextEditOrAnnotatedTextEditOrSnippetTextEdit.AsTextEdit(edit) }
    )
    TextDocumentEditOrCreateFileOrRenameFileOrDeleteFile.AsTextDocumentEdit(document)
}

/**
 * Converts checked byte ranges using the original document text.
 *
 * @throws IllegalArgumentException - for invalid or overlapping edits
 */
func sourceTextEdits(
    before: String,
    edits: Array<SourceTextEdit>,
    encoding: Encoding
): Array<TextEdit> {
    let text = Rope(before)
    validatedEdits(before, edits).map { edit => textEdit(text, edit, encoding) }
}

/**
 * Requires the client's advertised support before translating a resource operation.
 *
 * @throws IllegalArgumentException - if the operation is unsupported
 */
func requireResourceOperation(supported: Array<String>, operation: String): Unit {
    if (!supported.contains(operation)) {
        throw IllegalArgumentException("client does not support ${operation} resource operations")
    }
}
