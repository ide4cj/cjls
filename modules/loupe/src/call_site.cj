package loupe

import ginkgo.SyntaxNodePtr
import cjsyntax.{CjSyntaxNode, CjSyntaxToken, SyntaxKind}
import cjsyntax.ast.{Name, NameRef, RefExpr}
import loupe.db.AnalysisDatabase
import loupe.hir.*

/**
 * The source body currently reading `call`; stale and unavailable outputs keep the call-site fallback.
 */
func bodyOfExpressionExpansion(db: AnalysisDatabase, call: MacroCallId): ?DefId {
    if (call.inBody(db).isNone()) {
        return None
    }
    let def = DefId(db, ItemFile.Source(call.file(db)), call.item(db))
    let map = bodyWithSourceMap(db, def).sourceMap
    for (sources in [map.exprs, map.locals, map.types]) {
        if (
            sources
                .any {
                    one =>
                    match (one) {
                        case WrittenSource(source) => source.expansion == call
                        case SyntheticSource => false
                    }
                }
        ) {
            return def
        }
    }
    None
}

/**
 * What a name of the expansion of a macro call in an item (D117), an expression or statements with no item of their
 * own, is read as when its body does not read a current expansion: where the call stands, as cjc pastes
 * the tokens, with no hygiene.
 */
enum CallSiteName {
    /**
     * A token the macro copied from the source: as at this offset of the call's file.
     */
    | AtSource(Int64)
    /**
     * A plain name the macro wrote: what it resolved to in the scope where the call stands, in the body of the item.
     */
    | AtCall(DefId, BodyResolution)
}

/**
 * What `token`, at `offset` of the expansion of `call`, is read as (`CallSiteName`). `None` for a call on an item, for
 * what is neither copied nor a plain name (a member after a `.`, a type the macro wrote), for a name the expansion
 * itself declares, which only a body reading a current expansion knows, and for a call that is no expression (on a local
 * declaration).
 */
func callSiteNameOf(
    db: AnalysisDatabase,
    call: MacroCallId,
    token: CjSyntaxToken,
    offset: Int64
): ?CallSiteName {
    if (call.inBody(db).isNone()) {
        return None
    }
    if (
        let Some(source) <- sourceRangeOf(db, call, token.textRange) &&
            source.len == token.textRange.len
    ) {
        return CallSiteName.AtSource(source.start + offset - token.textRange.start)
    }
    let name = NameRef.cast(token.parent) ?? return None
    if (!(name.syntax.parent.map { one => RefExpr.canCast(one.kind) } ?? false)) {
        return None
    }
    let text = name.text()
    if (declares(expansionParse(db, call).syntaxNode(), text)) {
        return None
    }
    let node = bodyCallNodeOf(db, call) ?? return None
    let def = DefId(db, ItemFile.Source(call.file(db)), call.item(db))
    let expr = bodyWithSourceMap(db, def).sourceMap.exprAt(SyntaxNodePtr(node)) ?? return None
    CallSiteName.AtCall(def, resolveBodyName(db, def, exprScopes(db, def).scopeOf(expr), text))
}

/**
 * Whether a declaration under `root` declares `text`: a local, a parameter, a function.
 */
func declares(root: CjSyntaxNode, text: String): Bool {
    root
        .descendants()
        .any { node => node.kind == SyntaxKind.Name && (Name.cast(node)?.text() ?? "") == text }
}

/**
 * The hover of `token`, at `offset` of the expansion of `call`, as where the call stands (`callSiteNameOf`), its range
 * the token's.
 */
func hoverAtCallSite(
    db: AnalysisDatabase,
    call: MacroCallId,
    token: CjSyntaxToken,
    offset: Int64
): ?HoverResult {
    match (callSiteNameOf(db, call, token, offset)) {
        case Some(AtSource(at)) =>
            hoverIn(db, ItemFile.Source(call.file(db)), at)
                .map { found => HoverResult(token.textRange, found.items) }
        case Some(AtCall(def, resolution)) =>
            let items = Hovers(db, def, token).ofResolution(resolution)
            if (items.isEmpty()) { None } else { HoverResult(token.textRange, items) }
        case None => None
    }
}
