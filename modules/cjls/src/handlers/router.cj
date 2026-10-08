package cjls.handlers

import fjson.JsonValue
import rope.Encoding
import cjls.lsp_types.*
import cjls.lsp_ext.MemoryUsageRequestSpec
import cjls.server.*

/**
 * Every handler of the server, one line each.
 */
public func router(): Router {
    Router()
        .route(InitializeRequestSpec(), handleInitialize)
        .route(ShutdownRequestSpec()) {_: Context<Unit> => ()}
        // on the read loop, so it is acted on the moment it is read rather than queued behind the
        // work it cancels
        .route(CancelNotificationSpec()) {ctx: Context<CancelParams> => ctx.client.cancel(ctx.params.id)}
        .route(DidOpenTextDocumentNotificationSpec(), handleDidOpen)
        .route(DidChangeTextDocumentNotificationSpec(), handleDidChange)
        .route(DidCloseTextDocumentNotificationSpec(), handleDidClose)
        .route(InitializedNotificationSpec(), handleInitialized)
        .route(DidChangeWatchedFilesNotificationSpec(), handleDidChangeWatchedFiles)
        .route(DidChangeWorkspaceFoldersNotificationSpec(), handleDidChangeWorkspaceFolders)
        .route(WorkspaceSymbolRequestSpec(), handleWorkspaceSymbol)
        .route(DocumentSymbolRequestSpec(), handleDocumentSymbol)
        .route(DefinitionRequestSpec(), handleDefinition)
        .route(SelectionRangeRequestSpec(), handleSelectionRange)
        .route(DocumentFormattingRequestSpec(), handleFormatting)
        .route(DocumentDiagnosticRequestSpec(), handleDocumentDiagnostic)
        .route(SemanticTokensRequestSpec(), handleSemanticTokensFull)
        .route(SemanticTokensRangeRequestSpec(), handleSemanticTokensRange)
        .route(FoldingRangeRequestSpec(), handleFoldingRange)
        .route(MemoryUsageRequestSpec(), handleMemoryUsage)
        .publishDiagnostics(documentDiagnostics)
}

/**
 * What the server advertises, columns counted in `encoding`; it has to agree with `router()`.
 */
func capabilities(encoding: Encoding): ServerCapabilities {
    ServerCapabilities(
        positionEncoding: positionEncodingKind(encoding),
        textDocumentSync: TextDocumentSyncOptionsOrTextDocumentSyncKind.AsTextDocumentSyncOptions(
            TextDocumentSyncOptions(openClose: true, change: TextDocumentSyncKind.Incremental)),
        documentSymbolProvider: BooleanOrDocumentSymbolOptions.AsBoolean(true),
        definitionProvider: BooleanOrDefinitionOptions.AsBoolean(true),
        selectionRangeProvider: BooleanOrSelectionRangeOptionsOrSelectionRangeRegistrationOptions.AsBoolean(true),
        documentFormattingProvider: BooleanOrDocumentFormattingOptions.AsBoolean(true),
        // a file's diagnostics are its own, and nothing is reported for files not open (D14)
        diagnosticProvider: DiagnosticOptionsOrDiagnosticRegistrationOptions.AsDiagnosticOptions(
            DiagnosticOptions(interFileDependencies: false, workspaceDiagnostics: false)),
        // no `full/delta` until the server keeps what it sent (D19)
        semanticTokensProvider: SemanticTokensOptionsOrSemanticTokensRegistrationOptions.AsSemanticTokensOptions(
            SemanticTokensOptions(legend: semanticTokensLegend(),
                range: BooleanOrSemanticTokensOptionsRange.AsBoolean(true),
                full: BooleanOrSemanticTokensFullDelta.AsBoolean(true))),
        // a file's folds are its own: no `workspace/foldingRange/refresh`
        foldingRangeProvider: BooleanOrFoldingRangeOptionsOrFoldingRangeRegistrationOptions.AsBoolean(true),
        workspaceSymbolProvider: BooleanOrWorkspaceSymbolOptions.AsBoolean(true),
        workspace: WorkspaceOptions(workspaceFolders: WorkspaceFoldersServerCapabilities(supported: true,
            changeNotifications: StringOrBoolean.AsBoolean(true))),
        // the methods under `cjls/` it answers (D15, `docs/lsp-extensions.md`)
        experimental: JsonValue.JsonObject([("memoryUsage", JsonValue.JsonBool(true))])
    )
}
