package cjls.handlers

import stdxx.Nullable
import rope.Encoding
import loupe.vfs.VfsPath
import cjls.lsp_types.*
import cjls.server.*
import cjls.macros.LspHandler

/**
 * The server's version, as `modules/cjls/cjpm.toml` has it: `cog bump` rewrites both.
 */
const VERSION = "0.2.0"

@LspHandler
func handleInitialize(state: ServerState, params: InitializeParams): InitializeResult {
    state.encoding = negotiatedEncoding(params.capabilities)
    state.pushesDiagnostics = !pullsDiagnostics(params.capabilities)
    state.multilineTokens = takesMultilineTokens(params.capabilities)
    state.roots.add(all: workspaceRoots(params))
    let watching = params.capabilities.workspace.flatMap {workspace => workspace.didChangeWatchedFiles}
    state.watchesFiles = watching.flatMap {it => it.dynamicRegistration} ?? false
    state.relativePatterns = watching.flatMap {it => it.relativePatternSupport} ?? false
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

func positionEncodingKind(encoding: Encoding): PositionEncodingKind {
    match (encoding) {
        case Utf8 => PositionEncodingKind.UTF8
        case Utf16 => PositionEncodingKind.UTF16
        case Utf32 => PositionEncodingKind.UTF32
    }
}
