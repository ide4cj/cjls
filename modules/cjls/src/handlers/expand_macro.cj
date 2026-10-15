package cjls.handlers

import std.collection.collectArray
import std.fs.{Directory, exists, File, FileInfo, FSException, Path, remove}
import stdx.log.Logger
import stdxx.Nullable
import fjson.{JsonValue, RawJson}
import jsonrpc.{ErrorCode, ErrorLogValue, RpcException}
import rope.Rope
import loupe.{expandedMacro, ExpansionKind, macroCallAt, ShownExpansion}
import loupe.{expandFile, ExpandedFile, ExpandedPlace}
import loupe.{definitionAt, definitionInExpansion, highlightRelated, hoverAt, hoverInExpansion, NavigationTarget,
    RelatedHighlight}
import loupe.db.SourceFile
import loupe.vfs.{FileId, VfsPath}
import cjls.lsp_types.*
import cjls.lsp_ext.{EXPAND_MACRO_COMMAND, MacroExpansion}
import cjls.server.*
import cjls.macros.LspHandler

/**
 * What the macro call at the position, or the item it is in (`macroCallAt`), expands to, formatted (D60); one of std,
 * which the server writes itself, after a line saying so, and after the declaration it adds to. `null` off a call, on
 * one nothing expands, or in a document the server does not know.
 */
@LspHandler[readonly]
func handleExpandMacro(snap: ServerSnapshot, params: TextDocumentPositionParams): Nullable<MacroExpansion> {
    let file = fileOf(snap, params.textDocument.uri) ?? return Nullable.Null
    let at = macroCallAt(snap.analysis, file.fileId(snap.analysis), offsetOf(snap, file, params.position)) ??
        return Nullable.Null
    let expanded = expandedMacro(snap.analysis, at.call) ?? return Nullable.Null
    let shown = ShownExpansion.of(expanded.text).text
    Nullable.Value(match (expanded.kind) {
        case WorkspaceExpansion => MacroExpansion(name: expanded.name, expansion: shown, kind: "workspace")
        case StdExpansion =>
            let declaration = expanded.declaration.map {one => one.trimAsciiEnd() + "\n\n"} ?? ""
            MacroExpansion(name: expanded.name,
                expansion: "// cjls's own expansion of ${expanded.name}: signatures only, no bodies\n${declaration}${shown}",
                kind: "cjls")
    })
}

/**
 * "Expand macro" on a macro call that has an expansion, or in its item out of the item's bodies, where it would be
 * offered at every line (`macroCallAt`), its command `cjls.expandMacro` at the start of the range: to a client that
 * shows a document the server asks it to, and that asks for no kind in particular (the action has none).
 */
@LspHandler[readonly]
func handleCodeAction(snap: ServerSnapshot, params: CodeActionParams): Nullable<Array<CommandOrCodeAction>> {
    if (!snap.showsDocuments || !(params.context.only?.isEmpty() ?? true)) {
        return Nullable.Null
    }
    let file = fileOf(snap, params.textDocument.uri) ?? return Nullable.Null
    let at = macroCallAt(snap.analysis, file.fileId(snap.analysis), offsetOf(snap, file, params.range.start),
        inBody: false) ?? return Nullable.Null
    let expanded = expandedMacro(snap.analysis, at.call) ?? return Nullable.Null
    let argument = RawJson.of(TextDocumentPositionParams(textDocument: params.textDocument,
        position: params.range.start)).read<JsonValue>()
    let title = "Expand macro ${expanded.name}"
    let command = Command(title: title, command: EXPAND_MACRO_COMMAND, arguments: [argument])
    Nullable.Value([if (snap.codeActionLiterals) {
        CommandOrCodeAction.AsCodeAction(CodeAction(title: title, command: command))
    } else {
        CommandOrCodeAction.AsCommand(command)
    }])
}

/**
 * `cjls.expandMacro`: writes the expanded file of the document (`writeExpandedFile`) and asks the client to show it,
 * the expansion of the call at the position selected; answers `null` before the client answers. `null` for a document
 * the server does not know, or a position off any call with an expansion.
 *
 * @throws RpcException - `INVALID_PARAMS` for another command, or arguments not one `TextDocumentPositionParams`;
 * `REQUEST_FAILED` if the client shows no document, or the file cannot be written
 */
@LspHandler[readonly]
func handleExecuteCommand(snap: ServerSnapshot, client: Client, logger: Logger, params: ExecuteCommandParams): LSPAny {
    if (params.command != EXPAND_MACRO_COMMAND) {
        throw RpcException(ErrorCode.INVALID_PARAMS, "no such command: ${params.command}")
    }
    let position = match (params.arguments) {
        case Some(arguments) where arguments.size == 1 => try {
            RawJson.of(arguments[0]).read<TextDocumentPositionParams>()
        } catch (e: Exception) {
            throw RpcException(ErrorCode.INVALID_PARAMS, e.message)
        }
        case _ => throw RpcException(ErrorCode.INVALID_PARAMS, "${EXPAND_MACRO_COMMAND} takes a TextDocumentPositionParams")
    }
    if (!snap.showsDocuments) {
        throw RpcException(ErrorCode.REQUEST_FAILED, "the client shows no document the server asks it to")
    }
    let path = VfsPath.fromUri(position.textDocument.uri)
    let file = snap.sourceFile(path) ?? return JsonValue.JsonNull
    let at = macroCallAt(snap.analysis, file.fileId(snap.analysis), offsetOf(snap, file, position.position)) ??
        return JsonValue.JsonNull
    let (target, expanded) = writeExpandedFile(snap, path, file) ?? return JsonValue.JsonNull
    let selection = match (at.focus.flatMap {focus => expanded.fromExpansion(at.call, focus)}) {
        case Some(range) => Some(range)
        case None => expanded.expansionOf(at.call)
    }
    let text = Rope(expanded.text)
    showDocument(client, logger, ShowDocumentParams(uri: target.toUri(), takeFocus: true,
        selection: selection.map {range => lspRange(text, range.start, range.end, snap.encoding)}))
    JsonValue.JsonNull
}

/**
 * Asks the client to show a document, its answer waited for on a thread of its own: a document not shown is a
 * `DEBUG` of `logger`, a request that could not be sent a `WARN`.
 */
func showDocument(client: Client, logger: Logger, params: ShowDocumentParams): Unit {
    let answer = try {
        client.request(ShowDocumentRequestSpec(), params)
    } catch (e: Exception) {
        logger.warn("the document was not sent to be shown", [("uri", params.uri), ("error", e.message)])
        return
    }
    spawn {
        try {
            if (!answer.await().success) {
                logger.debug("the client did not show the document", [("uri", params.uri)])
            }
        } catch (e: Exception) {
            logger.debug("the client did not show the document", [("uri", params.uri), ("error", e.message)])
        } catch (e: Error) {
            logger.error("showing a document failed", [("cause", ErrorLogValue(e))])
        }
    }
}

/**
 * The first line of an expanded file, naming the source file by its path under the root.
 */
func expandedHeader(relative: String): String {
    "// generated by cjls from ${relative}: read-only, regenerated by \"Expand macro\""
}

/**
 * The expanded file of the source file at `path` in `cache` (`CacheDir.expandedFileOf`), and what it holds as the
 * snapshot has it (`loupe.expandFile`). `None` for a file outside the directory's project, or with no expansion.
 */
func expandedFileIn(snap: ServerSnapshot, cache: CacheDir, path: VfsPath, file: SourceFile): ?(VfsPath, ExpandedFile) {
    let target = cache.expandedFileOf(path) ?? return None
    let relative = String.join(path.segmentsUnder(cache.base) ?? return None, delimiter: "/")
    let expanded = expandFile(snap.analysis, file.fileId(snap.analysis), expandedHeader(relative)) ?? return None
    (target, expanded)
}

/**
 * Writes the expanded file of `file`, at `path`, read-only, as cjc's `--debug-macro` writes a `.cj.macrocall`, in the
 * cache directory of its project (D106). `None` for a virtual path, or a file with no expansion.
 *
 * @throws RpcException - `REQUEST_FAILED`, if it cannot be written
 */
func writeExpandedFile(snap: ServerSnapshot, path: VfsPath, file: SourceFile): ?(VfsPath, ExpandedFile) {
    if (path.filePath.isNone()) {
        return None
    }
    let cache = snap.cacheDirs.of(path, snap.roots) ??
        throw RpcException(ErrorCode.REQUEST_FAILED, "no cache directory can be written for ${path}")
    let (target, expanded) = expandedFileIn(snap, cache, path, file) ?? return None
    let targetPath = target.filePath ?? return None
    try {
        writeReadOnly(targetPath, expanded.text)
    } catch (e: FSException) {
        throw RpcException(ErrorCode.REQUEST_FAILED, "${targetPath} cannot be written: ${e.message}")
    }
    (target, expanded)
}

/**
 * Writes `text` to `path`, its directories made, and leaves it read-only where the platform lets it (on Windows the
 * attribute, if std may set it).
 *
 * @throws FSException - if it cannot be written
 */
func writeReadOnly(path: Path, text: String): Unit {
    let bytes = text.toArray()
    if (exists(path)) {
        if (File.readFrom(path) == bytes) {
            return
        }
        setWritable(path, true)
        remove(path)
    } else {
        Directory.create(path.parent, recursive: true)
    }
    File.writeTo(path, bytes)
    setWritable(path, false)
}

func setWritable(path: Path, writable: Bool): Unit {
    try {
        FileInfo(path).setWritable(writable)
    } catch (_: FSException) {
        // not permitted on Windows: the file stays writable
    }
}

/**
 * An expanded file open in the editor (`sourceOfExpanded`), as the snapshot would write it now: the source file it is
 * of, what it holds and where each piece comes from, and its text, positions are in.
 */
class ExpandedView {
    ExpandedView(let path: VfsPath, let source: SourceFile, let expanded: ExpandedFile, let text: Rope) {}

    func offsetOf(snap: ServerSnapshot, position: Position): Int64 {
        text.offsetOf(lineColumn(position), snap.encoding)
    }
}

/**
 * The view of the document at `uri`, if it is an expanded file the snapshot would write as the editor has it: `None`
 * once its source file changed since it was written, or the expansions in it, or it is no longer where the server
 * would write it (D103).
 */
func expandedViewOf(snap: ServerSnapshot, uri: DocumentUri): ?ExpandedView {
    let path = VfsPath.fromUri(uri)
    let sourcePath = sourceOfExpanded(path) ?? return None
    let document = snap.sourceFile(path) ?? return None
    let source = snap.sourceFile(sourcePath) ?? return None
    let cache = snap.cacheDirs.of(sourcePath, snap.roots) ?? return None
    let (target, expanded) = expandedFileIn(snap, cache, sourcePath, source) ?? return None
    if (target != path) {
        return None
    }
    let text = document.text(snap.analysis)
    if (text.toString() != expanded.text) {
        return None
    }
    ExpandedView(path, source, expanded, text)
}

/**
 * Whether the document at `uri` is an expanded file (`sourceOfExpanded`), which a request answers through its view,
 * if it has one, and never as a file of its own.
 */
func isExpandedDocument(uri: DocumentUri): Bool {
    isExpandedFile(VfsPath.fromUri(uri))
}

/**
 * Hover in an expanded file: as in its source file, or as in an expansion (`hoverInExpansion`), over the name's range
 * here if it is here.
 */
func hoverInView(snap: ServerSnapshot, view: ExpandedView, position: Position): Nullable<Hover> {
    let db = snap.analysis
    let (hover, range) = match (view.expanded.placeOf(view.offsetOf(snap, position))) {
        case Some(InSource(offset)) =>
            let hover = hoverAt(db, view.source.fileId(db), offset) ?? return Nullable.Null
            (hover, view.expanded.fromSource(hover.range))
        case Some(InExpansion(call, offset)) =>
            let hover = hoverInExpansion(db, call, offset) ?? return Nullable.Null
            (hover, view.expanded.fromExpansion(call, hover.range))
        case None => return Nullable.Null
    }
    Nullable.Value(Hover(contents: MarkupContentOrMarkedStringOrMarkedStrings.AsMarkupContent(
        hoverContent(hover, snap.hoverMarkdown)),
        range: range.map {it => lspRange(view.text, it.start, it.end, snap.encoding)}))
}

/**
 * Where a definition from an expanded file goes: its text, its document, and the target with its ranges in that text.
 */
struct Place {
    Place(let text: Rope, let uri: DocumentUri, let target: NavigationTarget) {}
}

/**
 * Go to definition in an expanded file: as in its source file, or as in an expansion (`definitionInExpansion`). A
 * declaration in what the file copied of its source goes here, one an expansion wrote to the expanded file of that
 * expansion's file, written first if it is another's; any other to its file.
 *
 * @throws RpcException - `REQUEST_FAILED`, if another expanded file cannot be written
 */
func definitionPlacesInView(snap: ServerSnapshot, view: ExpandedView, position: Position): Array<Place> {
    let db = snap.analysis
    let targets = match (view.expanded.placeOf(view.offsetOf(snap, position))) {
        case Some(InSource(offset)) => definitionAt(db, view.source.fileId(db), offset)
        case Some(InExpansion(call, offset)) => definitionInExpansion(db, call, offset)
        case None => return []
    }
    targets.iterator().filterMap {target: NavigationTarget => placeInView(snap, view, target)} |> collectArray
}

/**
 * Where `target`, found from `view`, goes (`definitionPlacesInView`); `None` for one an expansion wrote that its
 * expanded file does not show.
 */
func placeInView(snap: ServerSnapshot, view: ExpandedView, target: NavigationTarget): ?Place {
    let db = snap.analysis
    if (let Some(call) <- target.expansion) {
        let file = call.file(db)
        let (uri, expanded) = if (file == view.source) {
            (view.path.toUri(), view.expanded)
        } else {
            let (written, expanded) = writeExpandedFile(snap, snap.path(file.fileId(db)), file) ?? return None
            (written.toUri(), expanded)
        }
        let full = expanded.fromExpansion(call, target.fullRange) ?? return None
        let focus = expanded.fromExpansion(call, target.focusRange) ?? return None
        return Place(Rope(expanded.text), uri, NavigationTarget(target.fileId, full, focus))
    }
    if (target.fileId == view.source.fileId(db) && let Some(focus) <- view.expanded.fromSource(target.focusRange)) {
        let full = view.expanded.fromSource(target.fullRange) ?? focus
        return Place(view.text, view.path.toUri(), NavigationTarget(target.fileId, full, focus))
    }
    Place(db.sourceFile(target.fileId).getOrThrow().text(db), snap.path(target.fileId).toUri(), target)
}

/**
 * Highlights in an expanded file: those of its source file in what it copied of it; none in an expansion.
 */
func highlightsInView(snap: ServerSnapshot, view: ExpandedView, position: Position): Nullable<Array<DocumentHighlight>> {
    let db = snap.analysis
    let offset = match (view.expanded.placeOf(view.offsetOf(snap, position))) {
        case Some(InSource(offset)) => offset
        case _ => return Nullable.Null
    }
    let found = highlightRelated(db, view.source.fileId(db), offset).iterator().filterMap {
        highlight => view.expanded.fromSource(highlight.range).map {
            range => documentHighlight(view.text, RelatedHighlight(range, highlight.access), snap.encoding)
        }
    } |> collectArray
    if (found.isEmpty()) {
        Nullable.Null
    } else {
        Nullable.Value(found)
    }
}
