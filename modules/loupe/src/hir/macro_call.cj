package loupe.hir

import std.collection.*
import ginkgo.{SyntaxNodePtr, TextRange, TokenAtOffset}
import cjsyntax.{CjSyntaxNode, SyntaxKind}
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
    if (let Some(name) <- key.inBody) {
        let there = bodyMacroCalls(db, file).iterator().any {
            one => one.item == item && one.name == name && one.index == key.index
        }
        if (!there) {
            return None
        }
        return MacroCallId(db, file, item, key.index, Some(name))
    }
    let node = ids.node(item, parse(db, file).syntaxNode()) ?? return None
    if (key.index < 0 || key.index >= macroCallCountOf(node)) {
        return None
    }
    MacroCallId(db, file, item, key.index, None)
}

/**
 * The macro call of `file` whose head (`@` to the end of its attribute, or of its name) `offset` is on, the end
 * included, and that head: one in an item (`bodyMacroCalls`, D117), else one on an item or on a parameter of one
 * (D119); `None` off any head.
 */
public func macroCallUnder(db: AnalysisDatabase, file: SourceFile, offset: Int64): ?(MacroCallId, TextRange) {
    if (let Some(inItem) <- bodyCallUnder(db, file, offset)) {
        return inItem
    }
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
        // the item: the declaration under every call on it, or the innermost call on no declaration; for a call on a
        // parameter, the declaration whose parameter list holds it
        var node = call.syntax
        while (let Some(decl) <- MacroExpandDecl.cast(node).flatMap {one => one.decl()}) {
            node = decl.syntax
        }
        let ids = itemIdMap(db, file)
        if (MacroExpandDecl.cast(node).flatMap {one => one.param()}.isSome()) {
            node = (node.ancestors() |> filter {one: CjSyntaxNode => ids.idOf(SyntaxNodePtr(one)).isSome()} |> first) ??
                return None
        }
        let item = ids.idOf(SyntaxNodePtr(node)) ?? return None
        let index = macroCallIndexOf(node, call) ?? return None
        return (MacroCallId(db, file, item, index, None), headOf(call))
    }
    None
}

/**
 * The outermost macro call of each item of `file` around `offset` that has any, the innermost item first, and its
 * head; none of an item `offset` is in a body of (a `Block`, of the item or of a member) unless `inBody`.
 */
public func macroCallsAround(db: AnalysisDatabase, file: SourceFile, offset: Int64, inBody: Bool): Array<(MacroCallId,
    TextRange)> {
    let root = parse(db, file).syntaxNode()
    let token = match (root.tokenAtOffset(offset)) {
        case Single(token) => token
        case Between(_, right) => right
        case _ => return []
    }
    let ids = itemIdMap(db, file)
    let found = ArrayList<(MacroCallId, TextRange)>()
    var inBlock = false
    for (node in token.parent.ancestors()) {
        inBlock = inBlock || node.kind == SyntaxKind.Block
        // the item: the declaration under every call on it
        var decl = node
        while (let Some(inner) <- MacroExpandDecl.cast(decl).flatMap {one => one.decl()}) {
            decl = inner.syntax
        }
        let item = ids.idOf(SyntaxNodePtr(decl)) ?? continue
        let calls = macroCallsOf(decl)
        if (calls.isEmpty() || (inBlock && !inBody) || found.iterator().any {one => one[0].item(db) == item}) {
            continue
        }
        found.add((MacroCallId(db, file, item, 0, None), headOf(calls[0])))
    }
    found.toArray()
}

/**
 * The text of the declaration `call` is on, or of the parameter (D119), as written after its head: the calls inside
 * it included. `None` if its item is no longer there.
 */
public func declarationUnder(db: AnalysisDatabase, call: MacroCallId): ?String {
    if (call.inBody(db).isSome()) {
        return None
    }
    let file = call.file(db)
    let node = itemIdMap(db, file).node(call.item(db), parse(db, file).syntaxNode()) ?? return None
    let macroCall = macroCallAt(node, call.index(db)) ?? return None
    macroCall.decl().map {decl => decl.syntax.toString()} ?? macroCall.param().map {param => param.syntax.toString()}
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
    if (call.inBody(db).isSome()) {
        let syntax = bodyCallSyntaxOf(db, call) ?? return None
        return ("@" + syntax.name, syntax.head())
    }
    let file = call.file(db)
    let node = itemIdMap(db, file).node(call.item(db), parse(db, file).syntaxNode()) ?? return None
    let macroCall = macroCallAt(node, call.index(db)) ?? return None
    let names = macroCall.nameRefs() |> map {name => name.text()} |> collectArray
    ("@" + String.join(names, delimiter: "."), headOf(macroCall))
}

/**
 * The call whose expansion the analysis reads that shows what `call` adds: the call of a workspace macro read on its
 * top-level item, answered, if `call` is in its input (on a member, or within it on the item); else `call` itself if
 * it is expanded (`expandedCalls`); else that call of a workspace macro not answered yet. A call in an item (D117)
 * shows its own, if it is a workspace macro's. `None` for a call nothing expands.
 */
public func readCallOf(db: AnalysisDatabase, call: MacroCallId): ?MacroCallId {
    let file = call.file(db)
    if (call.inBody(db).isSome()) {
        if (workspaceCalls(db, file).iterator().any {one => one.call == call}) {
            return call
        }
        return None
    }
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
