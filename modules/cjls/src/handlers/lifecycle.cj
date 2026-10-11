package cjls.handlers

import stdx.log.Logger
import stdxx.Nullable
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
func handleInitialize(state: ServerState, client: Client, logger: Logger, params: InitializeParams): InitializeResult {
    state.encoding = negotiatedEncoding(params.capabilities)
    state.pushesDiagnostics = !pullsDiagnostics(params.capabilities)
    state.multilineTokens = takesMultilineTokens(params.capabilities)
    let folding = params.capabilities.textDocument.flatMap {textDocument => textDocument.foldingRange}
    state.lineFoldingOnly = folding.flatMap {it => it.lineFoldingOnly} ?? false
    state.foldingRangeLimit = folding.flatMap {it => it.rangeLimit}.map {it => Int64(it)}
    state.locationLinks = takesLocationLinks(params.capabilities)
    state.hoverMarkdown = takesHoverMarkdown(params.capabilities)
    state.roots.add(all: workspaceRoots(params))
    state.settings = initialSettings(params.initializationOptions, client, logger)
    let workspace = params.capabilities.workspace
    state.pullsSettings = workspace.flatMap {workspace => workspace.configuration} ?? false
    state.registersSettings = workspace.flatMap {workspace => workspace.didChangeConfiguration}.flatMap {
        it => it.dynamicRegistration
    } ?? false
    let watching = workspace.flatMap {workspace => workspace.didChangeWatchedFiles}
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

/**
 * Whether the client takes a hover's content as Markdown: one of the formats it lists.
 */
func takesHoverMarkdown(capabilities: ClientCapabilities): Bool {
    let formats = capabilities.textDocument.flatMap {textDocument => textDocument.hover}.flatMap {
        hover => hover.contentFormat
    } ?? []
    formats.contains(MarkupKind.Markdown)
}

func positionEncodingKind(encoding: Encoding): PositionEncodingKind {
    match (encoding) {
        case Utf8 => PositionEncodingKind.UTF8
        case Utf16 => PositionEncodingKind.UTF16
        case Utf32 => PositionEncodingKind.UTF32
    }
}
