package cjls.handlers

import fjson.JsonValue
import rope.Encoding
import cjls.lsp_types.*
import cjls.lsp_ext.{AnalysisStatsRequestSpec, EXPAND_MACRO_COMMAND, ExpandMacroRequestSpec, MemoryUsageRequestSpec}
import cjls.server.*

/**
 * Every handler of the server, one line each.
 */
public func router(): Router {
    Router()
        .route(InitializeRequestSpec(), handleInitialize)
        .route(ShutdownRequestSpec()) {
            ctx: Context<Unit> => if (let Some(work) <- ctx.loop.state.macroWork) {
                work.stop()
            }
        }
        // on the read loop, so it is acted on the moment it is read rather than queued behind the
        // work it cancels
        .route(CancelNotificationSpec()) {ctx: Context<CancelParams> => ctx.client.cancel(ctx.params.id)}
        .route(DidOpenTextDocumentNotificationSpec(), handleDidOpen)
        .route(DidChangeTextDocumentNotificationSpec(), handleDidChange)
        .route(DidCloseTextDocumentNotificationSpec(), handleDidClose)
        .route(InitializedNotificationSpec(), handleInitialized)
        .route(DidChangeWatchedFilesNotificationSpec(), handleDidChangeWatchedFiles)
        .route(DidChangeWorkspaceFoldersNotificationSpec(), handleDidChangeWorkspaceFolders)
        .route(DidChangeConfigurationNotificationSpec(), handleDidChangeConfiguration)
        .route(WorkspaceSymbolRequestSpec(), handleWorkspaceSymbol)
        .route(DocumentSymbolRequestSpec(), handleDocumentSymbol)
        .route(DefinitionRequestSpec(), handleDefinition)
        .route(DocumentHighlightRequestSpec(), handleDocumentHighlight)
        .route(ReferencesRequestSpec(), handleReferences)
        .route(ImplementationRequestSpec(), handleImplementation)
        .route(HoverRequestSpec(), handleHover)
        .route(CompletionRequestSpec(), handleCompletion)
        .route(CompletionResolveRequestSpec(), handleCompletionResolve)
        .route(SelectionRangeRequestSpec(), handleSelectionRange)
        .route(DocumentFormattingRequestSpec(), handleFormatting)
        .route(DocumentRangeFormattingRequestSpec(), handleRangeFormatting)
        .route(DocumentDiagnosticRequestSpec(), handleDocumentDiagnostic)
        .route(SemanticTokensRequestSpec(), handleSemanticTokensFull)
        .route(SemanticTokensRangeRequestSpec(), handleSemanticTokensRange)
        .route(FoldingRangeRequestSpec(), handleFoldingRange)
        .route(MemoryUsageRequestSpec(), handleMemoryUsage)
        .route(AnalysisStatsRequestSpec(), handleAnalysisStats)
        .route(ExpandMacroRequestSpec(), handleExpandMacro)
        .route(CodeActionRequestSpec(), handleCodeAction)
        .route(ExecuteCommandRequestSpec(), handleExecuteCommand)
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
        documentHighlightProvider: BooleanOrDocumentHighlightOptions.AsBoolean(true),
        referencesProvider: BooleanOrReferenceOptions.AsBoolean(true),
        implementationProvider: BooleanOrImplementationOptionsOrImplementationRegistrationOptions.AsBoolean(true),
        hoverProvider: BooleanOrHoverOptions.AsBoolean(true),
        // the detail and the documentation on resolve, so the list executes no query per item (D81, D111)
        completionProvider: CompletionOptions(triggerCharacters: ["."], resolveProvider: true),
        selectionRangeProvider: BooleanOrSelectionRangeOptionsOrSelectionRangeRegistrationOptions.AsBoolean(true),
        documentFormattingProvider: BooleanOrDocumentFormattingOptions.AsBoolean(true),
        documentRangeFormattingProvider: BooleanOrDocumentRangeFormattingOptions.AsBoolean(true),
        // a file's diagnostics depend on other files, and nothing is reported for files not open (D14, D100, D135)
        diagnosticProvider: DiagnosticOptionsOrDiagnosticRegistrationOptions.AsDiagnosticOptions(
            DiagnosticOptions(interFileDependencies: true, workspaceDiagnostics: false)),
        // no `full/delta` until the server keeps what it sent (D19)
        semanticTokensProvider: SemanticTokensOptionsOrSemanticTokensRegistrationOptions.AsSemanticTokensOptions(
            SemanticTokensOptions(legend: semanticTokensLegend(),
                range: BooleanOrSemanticTokensOptionsRange.AsBoolean(true),
                full: BooleanOrSemanticTokensFullDelta.AsBoolean(true))),
        // a file's folds are its own: no `workspace/foldingRange/refresh`
        foldingRangeProvider: BooleanOrFoldingRangeOptionsOrFoldingRangeRegistrationOptions.AsBoolean(true),
        workspaceSymbolProvider: BooleanOrWorkspaceSymbolOptions.AsBoolean(true),
        // "Expand macro", of no kind, and its command (D103)
        codeActionProvider: BooleanOrCodeActionOptions.AsBoolean(true),
        executeCommandProvider: ExecuteCommandOptions(commands: [EXPAND_MACRO_COMMAND]),
        workspace: WorkspaceOptions(workspaceFolders: WorkspaceFoldersServerCapabilities(supported: true,
            changeNotifications: StringOrBoolean.AsBoolean(true))),
        // the methods under `cjls/` it answers (D15, `docs/lsp-extensions.md`)
        experimental: JsonValue.JsonObject([("memoryUsage", JsonValue.JsonBool(true)),
            ("analysisStats", JsonValue.JsonBool(true)), ("expandMacro", JsonValue.JsonBool(true)), ("binarySourceRoots", JsonValue.JsonBool(true))])
    )
}
