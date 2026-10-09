package cjls.handlers

import std.collection.{ArrayList, HashSet}
import fjson.{JsonValue, RawJson}
import rope.Encoding
import cjls.lsp_types.*

/**
 * The methods every server takes unasked, and `didChangeWatchedFiles`, which the server registers
 * at run time with a client that watches files for it.
 */
private let UNADVERTISED = [InitializeRequestSpec.METHOD, InitializedNotificationSpec.METHOD, ShutdownRequestSpec.METHOD,
    CancelNotificationSpec.METHOD, DidChangeWatchedFilesNotificationSpec.METHOD]

/**
 * Whether a capability is on: `true`, or options.
 */
private func isOn(value: ?JsonValue): Bool {
    match (value) {
        case Some(JsonValue.JsonBool(on)) => on
        case Some(JsonValue.JsonObject(_)) => true
        case _ => false
    }
}

/**
 * The methods a client may send for one key of `ServerCapabilities`.
 *
 * @throws IllegalArgumentException - for a key this table does not know yet: it goes in, with the
 * methods it advertises
 */
private func methodsOf(key: String, value: JsonValue): Array<String> {
    let methods = ArrayList<String>()
    match (key) {
        case "positionEncoding" => ()
        case "textDocumentSync" =>
            if (isOn(value.get("openClose"))) {
                methods.add(all: [DidOpenTextDocumentNotificationSpec.METHOD, DidCloseTextDocumentNotificationSpec.METHOD])
            }
            // a `TextDocumentSyncKind`, `None` (0) for no changes
            if (let Some(JsonValue.JsonInteger(change)) <- value.get("change") && change != 0) {
                methods.add(DidChangeTextDocumentNotificationSpec.METHOD)
            }
            if (isOn(value.get("save"))) {
                methods.add(DidSaveTextDocumentNotificationSpec.METHOD)
            }
            if (isOn(value.get("willSave"))) {
                methods.add(WillSaveTextDocumentNotificationSpec.METHOD)
            }
            if (isOn(value.get("willSaveWaitUntil"))) {
                methods.add(WillSaveTextDocumentWaitUntilRequestSpec.METHOD)
            }
        case "documentSymbolProvider" => methods.add(DocumentSymbolRequestSpec.METHOD)
        case "documentFormattingProvider" => methods.add(DocumentFormattingRequestSpec.METHOD)
        case "foldingRangeProvider" => methods.add(FoldingRangeRequestSpec.METHOD)
        case "definitionProvider" => methods.add(DefinitionRequestSpec.METHOD)
        case "documentHighlightProvider" => methods.add(DocumentHighlightRequestSpec.METHOD)
        case "selectionRangeProvider" => methods.add(SelectionRangeRequestSpec.METHOD)
        case "workspaceSymbolProvider" => methods.add(WorkspaceSymbolRequestSpec.METHOD)
        case "diagnosticProvider" =>
            methods.add(DocumentDiagnosticRequestSpec.METHOD)
            if (isOn(value.get("workspaceDiagnostics"))) {
                methods.add(WorkspaceDiagnosticRequestSpec.METHOD)
            }
        case "semanticTokensProvider" =>
            let full = value.get("full")
            if (isOn(full)) {
                methods.add(SemanticTokensRequestSpec.METHOD)
            }
            if (isOn(full.flatMap {full => full.get("delta")})) {
                methods.add(SemanticTokensDeltaRequestSpec.METHOD)
            }
            if (isOn(value.get("range"))) {
                methods.add(SemanticTokensRangeRequestSpec.METHOD)
            }
        case "workspace" =>
            if (isOn(value.get("workspaceFolders").flatMap {folders => folders.get("changeNotifications")})) {
                methods.add(DidChangeWorkspaceFoldersNotificationSpec.METHOD)
            }
        // the methods under `cjls/`, by their names (`docs/lsp-extensions.md`)
        case "experimental" => methods.add(all: value.asObject()
            .filter {entry => isOn(entry[1])}
            .map {entry => "cjls/${entry[0]}"})
        case _ => throw IllegalArgumentException("no methods known for the capability \"${key}\"")
    }
    methods.toArray()
}

private func advertised(): HashSet<String> {
    let json = RawJson.of(capabilities(Encoding.Utf16)).read<JsonValue>()
    let methods = HashSet<String>(UNADVERTISED)
    for ((key, value) in json.asObject()) {
        methods.add(all: methodsOf(key, value))
    }
    methods
}

@Test
class CapabilitiesTest {
    @TestCase
    func everyRoutedMethodIsAdvertised() {
        // arrange
        let advertised = advertised()

        // act
        let unadvertised = router().methods.filter {method => !advertised.contains(method)}

        // assert
        @Expect(unadvertised, Array<String>())
    }

    @TestCase
    func everyAdvertisedMethodIsRouted() {
        // arrange
        let routed = HashSet<String>(router().methods)

        // act
        let unrouted = advertised().toArray().filter {method => !routed.contains(method)}

        // assert
        @Expect(unrouted, Array<String>())
    }
}
