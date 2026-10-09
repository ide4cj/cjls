package cjls.handlers

import std.collection.ArrayList
import std.fs.Path
import stdxx.Nullable
import fjson.JsonValue
import rope.Encoding
import loupe.vfs.VfsPath
import cjls.lsp_types.*
import cjls.server.*
import cjls.macros.LspHandler

/**
 * The server's version, as `modules/cjls/cjpm.toml` has it: `cog bump` rewrites both.
 */
const VERSION = "0.4.0"

@LspHandler
func handleInitialize(state: ServerState, params: InitializeParams): InitializeResult {
    state.encoding = negotiatedEncoding(params.capabilities)
    state.pushesDiagnostics = !pullsDiagnostics(params.capabilities)
    state.multilineTokens = takesMultilineTokens(params.capabilities)
    state.refreshesSemanticTokens = params.capabilities.workspace.flatMap {workspace => workspace.semanticTokens}
        .flatMap {semanticTokens => semanticTokens.refreshSupport} ?? false
    let folding = params.capabilities.textDocument.flatMap {textDocument => textDocument.foldingRange}
    state.lineFoldingOnly = folding.flatMap {it => it.lineFoldingOnly} ?? false
    state.foldingRangeLimit = folding.flatMap {it => it.rangeLimit}.map {it => Int64(it)}
    state.locationLinks = takesLocationLinks(params.capabilities)
    state.roots.add(all: workspaceRoots(params))
    state.linkedProjects.add(all: linkedProjects(params.initializationOptions))
    state.cangjieHome = pathOption(params.initializationOptions, "cangjieHome")
    state.cangjieSrc = pathOption(params.initializationOptions, "cangjieSrc")
    let watching = params.capabilities.workspace.flatMap {workspace => workspace.didChangeWatchedFiles}
    state.watchesFiles = watching.flatMap {it => it.dynamicRegistration} ?? false
    state.relativePatterns = watching.flatMap {it => it.relativePatternSupport} ?? false
    state.workDoneProgress = params.capabilities.window.flatMap {window => window.workDoneProgress} ?? false
    InitializeResult(capabilities: capabilities(state.encoding), serverInfo: ServerInfo(name: "cjls", version: VERSION))
}

/**
 * The folders of the workspace, or its root if it names none; only those on disk.
 */
func workspaceRoots(params: InitializeParams): Array<VfsPath> {
    match ((params.workspaceFolders, params.rootUri)) {
        case (Some(Nullable.Value(folders)), _) where !folders.isEmpty() => rootsOf(folders)
        case (_, Nullable.Value(uri)) => rootsOf([WorkspaceFolder(uri: uri, name: "")])
        case _ => Array<VfsPath>()
    }
}

/**
 * The projects `initializationOptions.linkedProjects` names, each an absolute path or a `file:`
 * URI; anything else is left out.
 */
func linkedProjects(options: ?JsonValue): Array<VfsPath> {
    let linked = match (options.flatMap {it => it.get("linkedProjects")}) {
        case Some(JsonValue.JsonArray(items)) => items
        case _ => return []
    }
    let paths = ArrayList<VfsPath>()
    for (item in linked) {
        match (item) {
            case JsonValue.JsonString(text) where text.startsWith("file:") =>
                let path = VfsPath.fromUri(text)
                if (path.filePath.isSome()) {
                    paths.add(path)
                }
            case JsonValue.JsonString(text) where Path(text).isAbsolute() => paths.add(VfsPath.file(text))
            case _ => ()
        }
    }
    paths.toArray()
}

/**
 * The path the option `name` of `initializationOptions` names, an absolute path or a `file:` URI:
 * the SDK (`cangjieHome`), its sources (`cangjieSrc`). `None` for anything else.
 */
func pathOption(options: ?JsonValue, name: String): ?String {
    match (options.flatMap {it => it.get(name)}) {
        case Some(JsonValue.JsonString(text)) where text.startsWith("file:") =>
            VfsPath.fromUri(text).filePath.map {path => path.toString()}
        case Some(JsonValue.JsonString(text)) where Path(text).isAbsolute() => text
        case _ => None
    }
}

/**
 * UTF-8 if the client can count columns in it, since that is what the text is kept in; UTF-16
 * otherwise, which every client can.
 */
func negotiatedEncoding(capabilities: ClientCapabilities): Encoding {
    let offered = capabilities.general.flatMap {general => general.positionEncodings} ?? []
    if (offered.any {kind => kind.value == PositionEncodingKind.UTF8.value}) {
        Encoding.Utf8
    } else {
        Encoding.Utf16
    }
}

/**
 * Whether the client asks for diagnostics itself (`textDocument/diagnostic`); one that does not is
 * pushed them (D14).
 */
func pullsDiagnostics(capabilities: ClientCapabilities): Bool {
    capabilities.textDocument.flatMap {textDocument => textDocument.diagnostic}.isSome()
}

/**
 * Whether the client takes a semantic token spanning lines; `false` unless it says so, as LSP has it.
 */
func takesMultilineTokens(capabilities: ClientCapabilities): Bool {
    capabilities.textDocument.flatMap {textDocument => textDocument.semanticTokens}.flatMap {
        semanticTokens => semanticTokens.multilineTokenSupport
    } ?? false
}

/**
 * Whether the client takes a definition as `LocationLink`s; `false` unless it says so, as LSP has it.
 */
func takesLocationLinks(capabilities: ClientCapabilities): Bool {
    capabilities.textDocument.flatMap {textDocument => textDocument.definition}.flatMap {
        definition => definition.linkSupport
    } ?? false
}

func positionEncodingKind(encoding: Encoding): PositionEncodingKind {
    match (encoding) {
        case Utf8 => PositionEncodingKind.UTF8
        case Utf16 => PositionEncodingKind.UTF16
        case Utf32 => PositionEncodingKind.UTF32
    }
}
