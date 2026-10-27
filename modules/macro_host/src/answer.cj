package macro_host

import std.collection.*
import loupe.db.*
import loupe.hir.MacroRequest
import macro_server.*

/**
 * What a call got from the server: its answer, or why it got none (the server exited, the deadline passed).
 */
public enum CallOutcome {
    | Answered(MacroResult)
    | Unanswered(String)
}

/**
 * Sends one call to a macro server and waits for what it gets: a test's is a fake.
 */
public interface Expander {
    func expand(call: MacroCallData): CallOutcome
}

/**
 * What the server answered for `request`, sent as `layout` put it, as the analysis keeps it (D98): its fingerprint;
 * the expansion printed as text, each token's span saying where it comes from, or none for a call that failed; the
 * items it set; what it reported, or that it failed if it said nothing.
 */
public func outputOf(
    request: MacroRequest,
    layout: WireLayout,
    outcome: CallOutcome,
    numbers: TokenNumbers
): MacroOutput {
    let name = request.definition.name
    let result =
        match (outcome) {
            case Answered(result) => result
            case Unanswered(reason) =>
                return MacroOutput(
                    request.fingerprint,
                    None,
                    [],
                    [
                        MacroDiagnostic(
                            MacroSeverity.MacroError,
                            SpanOrigin.FromCall,
                            "@${name} was not expanded: ${reason}",
                            ""
                        )
                    ]
                )
        }
    let diagnostics = ArrayList<MacroDiagnostic>()
    for (diagnostic in result.diags) {
        diagnostics.add(diagnosticOf(diagnostic, layout, name))
    }
    if (result.status == MACRO_FAILED) {
        if (diagnostics.isEmpty()) {
            diagnostics
                .add(
                    MacroDiagnostic(
                        MacroSeverity.MacroError,
                        SpanOrigin.FromCall,
                        "@${name} failed",
                        ""
                    )
                )
        }
        return MacroOutput(request.fingerprint, None, [], diagnostics.toArray())
    }
    let items = ArrayList<MacroItem>()
    for (item in result.items) {
        if (let Some(one) <- itemOf(item, layout, numbers)) {
            items.add(one)
        }
    }
    MacroOutput(
        request.fingerprint,
        mappedTextOf(printMacroTokens(result.tks, numbers), layout),
        items.toArray(),
        diagnostics.toArray()
    )
}

/**
 * Printed tokens as text whose spans say where each token comes from, as `layout` tells it by its position.
 */
func mappedTextOf(printed: PrintedTokens, layout: WireLayout): MappedText {
    let spans = ArrayList<MappedSpan>()
    for (token in printed.tokens where token.range.len > 0) {
        let begin = token.begin ?? continue
        if (let Some(origin) <- layout.originOf(begin.line, begin.column, token.range.len)) {
            spans.add(MappedSpan(token.range, origin))
        }
    }
    MappedText(printed.text, spans.toArray())
}

func diagnosticOf(diagnostic: Diagnostic, layout: WireLayout, name: String): MacroDiagnostic {
    // std.ast's `DiagReportLevel.ERROR.level()`
    let severity =
        if (diagnostic.diagSeverity == 0) {
            MacroSeverity.MacroError
        } else {
            MacroSeverity.MacroWarning
        }
    let origin =
        diagnostic
            .begin
            .flatMap {
                begin =>
                let size =
                    match (diagnostic.end) {
                        case Some(end) where end.line == begin.line && end.column > begin.column =>
                            Int64(end.column - begin.column)
                        case _ => 1
                    }
                layout.originOf(begin.line, begin.column, size)
            }
    var message = diagnostic.errorMessage ?? ""
    let hint = diagnostic.mainHint ?? ""
    // The macro's name is available here, unlike in the shared LSP conversion.
    if (message.isEmpty() && hint.isEmpty()) {
        message =
            if (severity == MacroSeverity.MacroError) {
                "@${name} reported an error"
            } else {
                "@${name} reported a warning"
            }
    }
    MacroDiagnostic(severity, origin, message, hint)
}

func itemOf(item: ItemInfo, layout: WireLayout, numbers: TokenNumbers): ?MacroItem {
    let key = item.key ?? return None
    let value =
        match (item.value) {
            case Some(AsSValue(text)) => MacroItemValue.StringItem(text)
            case Some(AsIValue(n)) => MacroItemValue.IntItem(n.val)
            case Some(AsBValue(flag)) => MacroItemValue.BoolItem(flag.val)
            case Some(AsTValue(tokens)) =>
                MacroItemValue
                    .TokensItem(mappedTextOf(printMacroTokens(tokens.val, numbers), layout))
            case _ => return None
        }
    MacroItem(key, value)
}
