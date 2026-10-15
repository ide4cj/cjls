package loupe.hir

import std.collection.*
import std.deriving.*
import ginkgo.{SyntaxNodePtr, TextRange}
import cjsyntax.{CjSyntaxNode, SyntaxKind}
import cjsyntax.ast.{Decl, MacroArgs, MacroAttr, MacroExpandDecl, MacroExpandExpr, NameRef}
import calca.*
import calca.macros.*
import loupe.db.*
import loupe.syntax.parse

/**
 * A macro called in an item, in a body or an initializer, not on the item (D117), as `bodyMacroCalls` finds it: its
 * item, the macro's name as written (`m.M`), its ordinal among the calls of that name in the item in the order their
 * `@`s are written, the names of the calls in the item whose input it is in, outermost first, and whether another call
 * is in its own input. Nothing in it says where it is, so an edit that moves it alone changes no query reading it.
 */
@Derive[Equatable]
public struct BodyMacroCall {
    public BodyMacroCall(
        public let item: ItemId,
        public let name: String,
        public let index: Int64,
        public let around: Array<String>,
        public let holdsCalls: Bool
    ) {}
}

/**
 * The macros called in the items of `file`, out of a false `@When`, as cjc runs them: item by item, a top-level item
 * before its members, and in an item innermost first, then left to right. A call in the tokens of arguments that do not
 * parse (D59) is no node, so none; nor one on a parameter, a call on its item (D119), nor a top-level call on no
 * declaration, whose arguments are its own call's input (D98).
 */
@CalcaTracked
public func bodyMacroCalls(db: AnalysisDatabase, file: SourceFile): Array<BodyMacroCall> {
    let root = parse(db, file).syntaxNode()
    let ids = itemIdMap(db, file)
    let filter = ActiveFilter.of(db, file)
    let found = ArrayList<BodyMacroCall>()
    for (top in activeItemTree(db, file).items) {
        for (item in [top].concat(top.members) where item.kind != ItemKind.MacroCall) {
            let node = ids.node(item.id, root) ?? continue
            for (one in BodyCallWalker(ids, filter, item.id).walk(node)) {
                found.add(BodyMacroCall(item.id, one.name, one.index, one.around, one.holdsCalls))
            }
        }
    }
    found.toArray()
}

/**
 * Where `call`, a call in a body (`MacroCallId.inBody`), is in the tree of its file now; `None` if it is no longer
 * there.
 */
func bodyCallSyntaxOf(db: AnalysisDatabase, call: MacroCallId): ?BodyCallSyntax {
    let name = call.inBody(db) ?? return None
    let file = call.file(db)
    let node = itemIdMap(db, file).node(call.item(db), parse(db, file).syntaxNode()) ?? return None
    let walker = BodyCallWalker(itemIdMap(db, file), ActiveFilter.of(db, file), call.item(db))
    (walker.walk(node) |> filter {one: FoundBodyCall => one.name == name && one.index == call.index(db)} |>
        map {one: FoundBodyCall => one.syntax} |> first)
}

/**
 * The call in an item of `file` (`bodyMacroCalls`) whose head `offset` is on, the end included, the innermost if
 * calls nest, and that head; `None` off any.
 */
func bodyCallUnder(db: AnalysisDatabase, file: SourceFile, offset: Int64): ?(MacroCallId, TextRange) {
    let root = parse(db, file).syntaxNode()
    let tokens = match (root.tokenAtOffset(offset)) {
        case Single(token) => [token]
        case Between(left, right) => [right, left]
        case _ => return None
    }
    let ids = itemIdMap(db, file)
    for (token in tokens) {
        for (node in token.parent.ancestors()) {
            let call = BodyCallSyntax.of(node) ?? continue
            if (!call.head().containsInclusive(offset)) {
                continue
            }
            let (item, itemNode) = (node.ancestors() |> filterMap {
                one: CjSyntaxNode => ids.idOf(SyntaxNodePtr(one)).map {id => (id, one)}
            } |> first) ?? break
            let walker = BodyCallWalker(ids, ActiveFilter.of(db, file), item)
            let found = (walker.walk(itemNode) |> filter {
                one: FoundBodyCall => one.syntax.syntax.textRange == node.textRange
            } |> first) ?? continue
            return (MacroCallId(db, file, item, found.index, Some(found.name)), found.syntax.head())
        }
    }
    None
}

/**
 * What `bodyMacroCalls` says of `call`, a call in a body; `None` if it is no longer there.
 */
func bodyMacroCallOf(db: AnalysisDatabase, call: MacroCallId): ?BodyMacroCall {
    let name = call.inBody(db) ?? return None
    bodyMacroCalls(db, call.file(db)) |> filter {
        one: BodyMacroCall => one.item == call.item(db) && one.name == name && one.index == call.index(db)
    } |> first
}

/**
 * A macro call in a body, written in an expression (`@M(…)`, `@A @B(…)`) or on a local declaration
 * (`@M func local() {}`).
 */
enum BodyCallSyntax {
    | InExpr(MacroExpandExpr)
    | OnLocalDecl(MacroExpandDecl)

    /**
     * The call `node` is, if it is one.
     */
    static func of(node: CjSyntaxNode): ?BodyCallSyntax {
        if (let Some(call) <- MacroExpandExpr.cast(node)) {
            return InExpr(call)
        }
        MacroExpandDecl.cast(node).map {call => OnLocalDecl(call)}
    }

    prop syntax: CjSyntaxNode {
        get() {
            match (this) {
                case InExpr(call) => call.syntax
                case OnLocalDecl(call) => call.syntax
            }
        }
    }

    /**
     * The macro's name as written: `M`, `m.M`.
     */
    prop name: String {
        get() {
            let names = match (this) {
                case InExpr(call) => call.nameRefs()
                case OnLocalDecl(call) => call.nameRefs()
            }
            String.join(names |> map {one: NameRef => one.text()} |> collectArray, delimiter: ".")
        }
    }

    func macroAttr(): ?MacroAttr {
        match (this) {
            case InExpr(call) => call.macroAttr()
            case OnLocalDecl(call) => call.macroAttr()
        }
    }

    func macroArgs(): ?MacroArgs {
        match (this) {
            case InExpr(call) => call.macroArgs()
            case OnLocalDecl(call) => call.macroArgs()
        }
    }

    /**
     * What the call is given after its head when it is not `(…)`: the call nested in it (`@A @B(…)`), or the
     * declaration it is on.
     */
    func rest(): ?CjSyntaxNode {
        match (this) {
            case InExpr(call) => call.macroExpandExpr().map {one => one.syntax}
            case OnLocalDecl(call) => call.decl().map {one => one.syntax}
        }
    }

    /**
     * From the `@` to the end of the attribute, or of the name: where what its macro wrote is said to come from.
     */
    func head(): TextRange {
        let whole = syntax.textRange.start
        let start = match (this) {
            case InExpr(call) => call.atToken()?.textRange.start ?? call.atBangToken()?.textRange.start ?? whole
            case OnLocalDecl(call) => call.atToken()?.textRange.start ?? call.atBangToken()?.textRange.start ?? whole
        }
        if (let Some(attr) <- macroAttr()) {
            return TextRange(start, attr.syntax.textRange.end)
        }
        let names = match (this) {
            case InExpr(call) => call.nameRefs()
            case OnLocalDecl(call) => call.nameRefs()
        }
        let ends = names |> map {one: NameRef => one.syntax.textRange.end} |> collectArray
        TextRange(start, ends.get(ends.size - 1) ?? (start + 1))
    }
}

/**
 * A call `BodyCallWalker` found: its syntax and what `BodyMacroCall` says of it.
 */
struct FoundBodyCall {
    FoundBodyCall(
        let syntax: BodyCallSyntax,
        let name: String,
        let index: Int64,
        let around: Array<String>,
        let holdsCalls: Bool
    ) {}
}

/**
 * Finds the macro calls in one item's node: not in another item (a member), nor under a false `@When`, nor on a
 * parameter (D119). Each gets its ordinal by the order of the `@`s, and is given after the calls in its input.
 */
class BodyCallWalker {
    private let ordinals = HashMap<String, Int64>()
    private let found = ArrayList<FoundBodyCall>()

    BodyCallWalker(private let ids: ItemIdMap, private let filter: ActiveFilter, private let item: ItemId) {}

    func walk(node: CjSyntaxNode): Array<FoundBodyCall> {
        visit(node, [])
        found.toArray()
    }

    /**
     * Whether a call is under `node`.
     */
    private func visit(node: CjSyntaxNode, around: Array<String>): Bool {
        var any = false
        for (child in node.children()) {
            if (!filter.isActive(child) || isAnotherItem(child) || isOnParam(child)) {
                continue
            }
            match (BodyCallSyntax.of(child)) {
                case Some(call) =>
                    let name = call.name
                    let index = ordinals.get(name) ?? 0
                    ordinals[name] = index + 1
                    let holdsCalls = visit(child, around.concat([lastSegmentOf(name)]))
                    found.add(FoundBodyCall(call, name, index, around, holdsCalls))
                    any = true
                case None => any = visit(child, around) || any
            }
        }
        any
    }

    /**
     * Whether `node` is an item other than the walked one, or a macro call on one: a member.
     */
    private func isAnotherItem(node: CjSyntaxNode): Bool {
        var decl = node
        while (let Some(inner) <- MacroExpandDecl.cast(decl).flatMap {one => one.decl()}) {
            decl = inner.syntax
        }
        match (ids.idOf(SyntaxNodePtr(decl))) {
            case Some(id) => id != item
            case None => false
        }
    }

    /**
     * Whether `node` is a macro call on a parameter: the innermost of its chain on it (`@A @M let a: Int64`).
     */
    private func isOnParam(node: CjSyntaxNode): Bool {
        var call = MacroExpandDecl.cast(node) ?? return false
        while (let Some(inner) <- call.decl().flatMap {decl => MacroExpandDecl.cast(decl.syntax)}) {
            call = inner
        }
        call.param().isSome()
    }
}
