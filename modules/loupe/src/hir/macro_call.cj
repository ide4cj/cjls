package loupe.hir

import std.collection.*
import ginkgo.{SyntaxNodePtr, TextRange, TokenAtOffset}
import cjsyntax.CjSyntaxNode
import cjsyntax.ast.MacroExpandDecl
import loupe.db.*
import loupe.syntax.parse

/**
 * The call `key` names in `file` (`macroCallKeyOf`): its item still there, with a macro call at its index; `None`
 * otherwise.
 */
public func macroCallOf(db: AnalysisDatabase, file: SourceFile, key: MacroCallKey): ?MacroCallId {
    let ids = itemIdMap(db, file)
    let item = (ids.all |> filter {id: ItemId => id.toString() == key.item} |> first) ?? return None
    let node = ids.node(item, parse(db, file).syntaxNode()) ?? return None
    if (key.index < 0 || key.index >= macroCallsOf(node).size) {
        return None
    }
    MacroCallId(db, file, item, key.index)
}

/**
 * The macro call on an item of `file` whose head (`@` to the end of its attribute, or of its name) `offset` is on, the
 * end included, and that head; `None` off any head, or on a call on no item (one in a body).
 */
public func macroCallUnder(db: AnalysisDatabase, file: SourceFile, offset: Int64): ?(MacroCallId, TextRange) {
    let root = parse(db, file).syntaxNode()
    let tokens = match (root.tokenAtOffset(offset)) {
        case Single(token) => [token]
        case Between(left, right) => [right, left]
        case _ => return None
    }
    for (token in tokens) {
        let call = (token.parent.ancestors() |> filterMap {node: CjSyntaxNode => MacroExpandDecl.cast(node)} |> filter {
            one: MacroExpandDecl => headOf(one).containsInclusive(offset)
        } |> first) ?? continue
        // the item: the declaration under every call on it, or the innermost call on no declaration
        var node = call.syntax
        while (let Some(decl) <- MacroExpandDecl.cast(node).flatMap {one => one.decl()}) {
            node = decl.syntax
        }
        let item = itemIdMap(db, file).idOf(SyntaxNodePtr(node)) ?? return None
        let index = macroCallsOf(node).map {one => one.syntax.textRange}.indexOf(call.syntax.textRange) ?? return None
        return (MacroCallId(db, file, item, index), headOf(call))
    }
    None
}

/**
 * The head of `call` from its `@`, doc comments and annotations before it left out.
 */
func headOf(call: MacroExpandDecl): TextRange {
    let head = macroHeadOf(call)
    let at = call.atToken()?.textRange.start ?? call.atBangToken()?.textRange.start ?? head.start
    TextRange(at, head.end)
}

/**
 * The macro's name as `call` writes it, `@` and its path (`@Derive`, `@m.ms.M`), its attribute left out; and its
 * head (`macroCallUnder`). `None` if its item is no longer there.
 */
public func macroCallHeadOf(db: AnalysisDatabase, call: MacroCallId): ?(String, TextRange) {
    let file = call.file(db)
    let node = itemIdMap(db, file).node(call.item(db), parse(db, file).syntaxNode()) ?? return None
    let macroCall = macroCallsOf(node).get(call.index(db)) ?? return None
    let names = macroCall.nameRefs() |> map {name => name.text()} |> collectArray
    ("@" + String.join(names, delimiter: "."), headOf(macroCall))
}

/**
 * The call whose expansion the analysis reads that shows what `call` adds: the call of a workspace macro read on its
 * top-level item, answered, if `call` is in its input (on a member, or within it on the item); else `call` itself if
 * it is expanded (`expandedCalls`); else that call of a workspace macro not answered yet. `None` for a call nothing
 * expands.
 */
public func readCallOf(db: AnalysisDatabase, call: MacroCallId): ?MacroCallId {
    let file = call.file(db)
    let expanded = expandedCalls(db, file)
    let item = call.item(db)
    let top = (itemTree(db, file).items |> filter {
        one: Item => one.id == item || one.members.iterator().any {member => member.id == item}
    } |> map {one: Item => one.id} |> first) ?? return None
    let read = (workspaceCalls(db, file) |> filter {one: WorkspaceCall => one.read && one.top == top} |>
        map {one: WorkspaceCall => one.call} |> first).flatMap {
            one: MacroCallId => if (item != top || call.index(db) >= one.index(db)) {
                Some(one)
            } else {
                None<MacroCallId>
            }
        }
    match (read) {
        case Some(one) where expanded.contains(one) => one
        case _ where expanded.contains(call) => call
        case _ => read
    }
}

/**
 * The anchor of the spans of the expansion of `call`, a call of a workspace macro the analysis reads: the start of its
 * top-level item (`anchorOf`).
 */
func anchorOfCall(db: AnalysisDatabase, call: MacroCallId): ?Int64 {
    let file = call.file(db)
    let top = (workspaceCalls(db, file) |> filter {one: WorkspaceCall => one.call == call} |> first)?.top ??
        return None
    anchorOf(itemIdMap(db, file), parse(db, file).syntaxNode(), top)
}

/**
 * The range of the file of `call` that `range` of the text of its expansion was copied from (`MappedText.originOf`);
 * `None` for text the macro wrote, and for an expansion of std's macro, all of which the analysis writes.
 */
public func sourceRangeOf(db: AnalysisDatabase, call: MacroCallId, range: TextRange): ?TextRange {
    let expansion = macroExpansion(db, call)
    if (expansion.spans.isEmpty()) {
        return None
    }
    match (MappedText(expansion.text, expansion.spans).originOf(range)) {
        case Some(FromSource(source)) => source.shift(anchorOfCall(db, call) ?? return None)
        case _ => None
    }
}

/**
 * The range of the text of the expansion of `call` that comes from `range` of its file: from the first span whose
 * origin meets it to the last, the part copied of a span copied whole; what a call nested in its input added comes
 * from that call's head. `None` if none does, and for an expansion of std's macro.
 */
public func expansionRangeOf(db: AnalysisDatabase, call: MacroCallId, range: TextRange): ?TextRange {
    let expansion = macroExpansion(db, call)
    if (expansion.spans.isEmpty()) {
        return None
    }
    let wanted = range.shift(-(anchorOfCall(db, call) ?? return None))
    var found: ?TextRange = None
    for (span in expansion.spans) {
        let source = match (span.origin) {
            case FromSource(source) => source
            case FromCall => continue
        }
        let common = source.intersect(wanted) ?? continue
        if (common.isEmpty() && !(source.isEmpty() || wanted.isEmpty())) {
            continue
        }
        let part = if (source.len == span.range.len) {
            TextRange(span.range.start + common.start - source.start, span.range.start + common.end - source.start)
        } else {
            span.range
        }
        found = found.map {one => one.cover(part)} ?? part
    }
    found
}
