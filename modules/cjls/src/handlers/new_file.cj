package cjls.handlers

import std.collection.{collectArray, HashMap}
import stdx.log.Logger
import stdxx.Nullable
import rope.Rope
import loupe.vfs.VfsPath
import cjls.lsp_types.*
import cjls.server.*

/**
 * A document opened blank is given its `package` line (#294), as Metals gives it: at once if no
 * load runs, else once the load ends, with the project that names its package. Not on
 * `workspace/didCreateFiles`, as gopls does, which Neovim never sends: the line goes with a document
 * an editor opens, never to a file on disk alone.
 */
func packageLineOnOpen(loop: Loop, client: Client, logger: Logger, path: VfsPath): Unit {
    let state = loop.state
    if (state.fileContents(path).map {text => !isBlank(text)} ?? true) {
        return
    }
    if (state.loading) {
        state.blankDuringLoad.add(path)
    } else if (let Some(edit) <- packageLineEdit(state, path)) {
        applyEdit(loop, client, logger, edit)
    }
}

/**
 * The edits that give the documents opened blank while a load ran their `package` line, those still
 * open and blank; once the load ended.
 */
func packageLinesAfterLoad(state: ServerState): Array<ApplyWorkspaceEditParams> {
    let paths = collectArray(state.blankDuringLoad)
    state.blankDuringLoad.clear()
    collectArray(paths.iterator().filterMap {path => packageLineEdit(state, path)})
}

/**
 * The edit that gives the document open at `path` its `package` line, the whole of its blank text
 * replaced: `None` if the setting is off, the client applies no edits, the document is not open or
 * not blank, or the project names no package for it. Of the version the document is at, if the
 * client takes one, so a document typed in since is left alone.
 */
func packageLineEdit(state: ServerState, path: VfsPath): ?ApplyWorkspaceEditParams {
    if (!state.settings.newFilePackage || !state.appliesEdits) {
        return None
    }
    let version = state.openDocuments.get(path) ?? return None
    let text = state.fileContents(path) ?? return None
    if (!isBlank(text)) {
        return None
    }
    let name = state.packageOfNewFile(path) ?? return None
    let line = "package ${name}"
    let edit = TextEdit(range: lspRange(text, 0, text.size, state.encoding), newText: "${line}\n\n")
    let uri = path.toUri()
    let workspaceEdit = if (state.versionedEdits) {
        let document = TextDocumentEdit(textDocument: OptionalVersionedTextDocumentIdentifier(uri: uri,
            version: Nullable.Value(version)), edits: [TextEditOrAnnotatedTextEditOrSnippetTextEdit.AsTextEdit(edit)])
        WorkspaceEdit(documentChanges: [TextDocumentEditOrCreateFileOrRenameFileOrDeleteFile.AsTextDocumentEdit(document)])
    } else {
        WorkspaceEdit(changes: HashMap<DocumentUri, Array<TextEdit>>([(uri, [edit])]))
    }
    ApplyWorkspaceEditParams(label: line, edit: workspaceEdit)
}

/**
 * Asks the client to apply `edit`, and waits for its answer on a thread of its own: an edit not
 * applied is a `DEBUG` of `logger`, as a document typed in since is no failure.
 */
func applyEdit(loop: Loop, client: Client, logger: Logger, edit: ApplyWorkspaceEditParams): Unit {
    let answer = try {
        client.request(ApplyWorkspaceEditRequestSpec(), edit)
    } catch (e: Exception) {
        logger.warn("the edit was not sent", [("error", e.message)])
        return
    }
    loop.start(logger) {
        let result = try {
            answer.await()
        } catch (e: Exception) {
            logger.debug("the edit was not answered", [("error", e.message)])
            return
        }
        if (!result.applied) {
            logger.debug("the edit was not applied", [("label", edit.label ?? ""),
                ("reason", result.failureReason ?? "")])
        }
    }
}

/**
 * Whether `text` is whitespace alone: Neovim opens a file new, or empty, as `"\n"`.
 */
func isBlank(text: Rope): Bool {
    text.chunks().all {
        chunk => chunk.toArray().iterator().all {byte => byte == b' ' || byte == b'\t' || byte == b'\n' || byte == b'\r'}
    }
}
