package loupe.hir

import std.collection.{ArrayList, HashMap, HashSet}
import std.sort.sort
import cjsyntax.{CjSyntaxNode, SyntaxKind}
import cjsyntax.ast.{Decl, MacroAttr, MacroExpandDecl}
import ginkgo.TextRange
import loupe.db.{AnalysisDatabase, MacroCallKey, MappedSpan, MappedText, SourceFile, SpanOrigin}
import loupe.syntax.parse

/**
 * The text a `MacroRequest` gives, built piece by piece: text of the source, copied, and outputs of other calls.
 */
class MappedTextBuilder {
    private let text = StringBuilder()
    private let spans = ArrayList<MappedSpan>()
    private var size = 0

    MappedTextBuilder(private let source: String, private let anchor: Int64) {}

    /**
     * Copies `range` of the source.
     */
    func copy(range: TextRange): Unit {
        if (range.len <= 0) {
            return
        }
        text.append(source[range.start..range.end])
        spans
            .add(
                MappedSpan(
                    TextRange.at(size, range.len),
                    SpanOrigin.FromSource(TextRange.at(range.start - anchor, range.len))
                )
            )
        size += range.len
    }

    /**
     * Appends the output of the call whose head is `head`: what its macro wrote is said to come from there.
     */
    func paste(output: MappedText, head: TextRange): Unit {
        text.append(output.text)
        for (span in output.spans) {
            let origin =
                match (span.origin) {
                    case FromCall =>
                        SpanOrigin.FromSource(TextRange(head.start - anchor, head.end - anchor))
                    case other => other
                }
            spans.add(MappedSpan(TextRange(span.range.start + size, span.range.end + size), origin))
        }
        size += output.text.size
    }

    func build(): MappedText {
        MappedText(text.toString(), spans.toArray())
    }
}

/**
 * What is between the brackets of `node`, `@M[…]`'s or `@M(…)`'s: after its first token if it is `open`, up to its
 * last if it is `close`. Not the first `close` among its tokens, which may be one nested in it (`@M[a: [1]]`).
 */
func innerRangeOf(node: CjSyntaxNode, open: SyntaxKind, close: SyntaxKind): TextRange {
    let start =
        match (node.firstToken()) {
            case Some(first) where first.kind == open => first.textRange.end
            case _ => node.textRange.start
        }
    let end =
        match (node.lastToken()) {
            case Some(last) where last.kind == close && last.textRange.start >= start =>
                last.textRange.start
            case _ => node.textRange.end
        }
    TextRange(start, end)
}

/**
 * Writes the requests of the calls the server runs in a file: their input is the text of the source, where each call
 * nested in it is its output (the last that succeeded).
 */
class MacroInputComposer {
    private let root: CjSyntaxNode
    private let ids: ItemIdMap
    private let tree: ItemTree
    private let source: String
    private let served: HashMap<MacroCallKey, ServerCall>
    private let bodySyntax = HashMap<MacroCallId, BodyCallSyntax>()
    private let bodyCalls = ArrayList<(ServerCall, BodyCallSyntax)>()
    private let requests = HashMap<MacroCallId, MacroRequest>()

    MacroInputComposer(
        calls: Array<ServerCall>,
        private let db: AnalysisDatabase,
        private let file: SourceFile
    ) {
        root = parse(db, file).syntaxNode()
        ids = itemIdMap(db, file)
        tree = itemTree(db, file)
        source = file.text(db).toString()
        served = HashMap(calls.map { one => (macroCallKeyOf(db, one.call), one) })
        collectBodyCalls(calls)
    }

    private func collectBodyCalls(calls: Array<ServerCall>): Unit {
        let walked = HashSet<ItemId>()
        let filter = ActiveFilter.of(db, file)
        for (one in calls where one.call.inBody(db).isSome()) {
            let item = one.call.item(db)
            if (!walked.add(item)) {
                continue
            }
            let node = ids.node(item, root) ?? continue
            for (found in BodyCallWalker(ids, filter, item).walk(node)) {
                let key = MacroCallKey(item.toString(), found.index, inBody: Some(found.name))
                let call = served.get(key) ?? continue
                bodySyntax[call.call] = found.syntax
                bodyCalls.add((call, found.syntax))
            }
        }
        sort(
            bodyCalls,
            by: { a, b => a[1].syntax.textRange.start.compare(b[1].syntax.textRange.start) }
        )
    }

    /**
     * The request for `call`; `None` if a call nested in its input has no expansion, or its item is not there. The
     * input of a call on a parameter (D119) is the parameter, as cjc gives it.
     */
    func request(call: ServerCall): ?MacroRequest {
        if (let Some(cached) <- requests.get(call.call)) {
            return Some(cached)
        }
        let result = buildRequest(call)
        if (let Some(ready) <- result) {
            requests[call.call] = ready
        }
        result
    }

    private func buildRequest(call: ServerCall): ?MacroRequest {
        if (call.call.inBody(db).isSome()) {
            return requestInItem(call)
        }
        let item = call.call.item(db)
        let index = call.call.index(db)
        let anchor = anchorOf(ids, root, call.top) ?? return None
        let node = ids.node(item, root) ?? return None
        let (chain, position) = macroCallChainAt(node, index) ?? return None
        let macroCall = chain.calls[position]
        let attrs = mappedAttribute(macroCall.macroAttr(), anchor)
        let builder = MappedTextBuilder(source, anchor)
        let children = ArrayList<MacroChild>()
        let ready =
            if (position + 1 < chain.calls.size) {
                chainFrom(item, chain, position + 1, builder, children)
            } else if (let Some(decl) <- macroCall.decl()) {
                declaration(item, decl.syntax, builder, children)
            } else if (let Some(param) <- macroCall.param()) {
                bodyInput(param.syntax.textRange, builder, children)
            } else if (let Some(args) <- macroCall.macroArgs()) {
                bodyInput(
                    innerRangeOf(args.syntax, SyntaxKind.LParen, SyntaxKind.RParen),
                    builder,
                    children
                )
            } else {
                true
            }
        if (!ready) {
            return None
        }
        let input = builder.build()
        let parents = parentsOf(call.top, item, index)
        makeRequest(call, attrs, input, parents, children)
    }

    /**
     * The request for `call`, a call in an item (D117): its input what is between its parentheses, or the local
     * declaration it is on; its parents the macros on the items around it, then the calls in the item whose input it
     * is in. `None` until the calls in its input have outputs, or once it is gone.
     */
    private func requestInItem(call: ServerCall): ?MacroRequest {
        let found = bodyMacroCallOf(db, call.call) ?? return None
        let syntax = bodySyntax.get(call.call) ?? return None
        let anchor = anchorOf(ids, root, call.top) ?? return None
        let attrs = mappedAttribute(syntax.macroAttr(), anchor)
        let builder = MappedTextBuilder(source, anchor)
        let children = ArrayList<MacroChild>()
        let range =
            match ((syntax.macroArgs(), syntax.rest())) {
                case (Some(args), _) =>
                    innerRangeOf(args.syntax, SyntaxKind.LParen, SyntaxKind.RParen)
                case (None, Some(rest)) => rest.textRange
                case _ => TextRange.at(syntax.syntax.textRange.end, 0)
            }
        if (!bodyInput(range, builder, children)) {
            return None
        }
        let input = builder.build()
        let item = call.call.item(db)
        let parents = parentsOf(call.top, item, macroCountOf(item)).concat(found.around)
        makeRequest(call, attrs, input, parents, children)
    }

    private func mappedAttribute(attr: ?MacroAttr, anchor: Int64): ?MappedText {
        attr
            .map {
                one =>
                let builder = MappedTextBuilder(source, anchor)
                builder.copy(innerRangeOf(one.syntax, SyntaxKind.LBracket, SyntaxKind.RBracket))
                builder.build()
            }
    }

    private func makeRequest(
        call: ServerCall,
        attrs: ?MappedText,
        input: MappedText,
        parents: Array<String>,
        children: ArrayList<MacroChild>
    ): MacroRequest {
        let fingerprint =
            fingerprintOf(
                call.definition,
                call.definition.libraryStamp(db),
                attrs,
                input,
                parents,
                children
            )
        let current = macroOutputOf(db, call.call)?.fingerprint == fingerprint
        MacroRequest(
            call.call,
            call.definition,
            attrs,
            input,
            parents,
            children.toArray(),
            fingerprint,
            current
        )
    }

    /**
     * Splices source calls into a slice of an input. Replacing the outermost call also replaces its descendants;
     * their messages still precede its own, as cjc gives an ancestor every nested call's messages.
     */
    private func bodyInput(
        range: TextRange,
        builder: MappedTextBuilder,
        children: ArrayList<MacroChild>
    ): Bool {
        var at = range.start
        for ((call, syntax) in bodyCalls) {
            let span = syntax.syntax.textRange
            if (span.start < at || span.end > range.end) {
                continue
            }
            let output = macroOutputOf(db, call.call) ?? return false
            let expansion = output.expansion ?? return false
            builder.copy(TextRange(at, span.start))
            builder.paste(expansion, syntax.head())
            children.add(all: request(call).map { one => one.children } ?? [])
            children.add(MacroChild(call.definition.name, output.items))
            at = span.end
        }
        builder.copy(TextRange(at, range.end))
        true
    }

    /**
     * How many macros are called on `item`.
     */
    private func macroCountOf(item: ItemId): Int64 {
        for (one in tree.items) {
            if (one.id == item) {
                return one.macros.size
            }
            for (member in one.members where member.id == item) {
                return member.macros.size
            }
        }
        0
    }

    /**
     * Writes the calls of `chain` from `from` on, on `item` or on one of its parameters (D119), and what they are
     * on: up to the first call the server runs the text of the source (a macro neither of the workspace nor of std,
     * which nothing expands), then that call's output. A call of std's `@Derive` the server has no expansion of, its
     * run failed, is expanded as cjc expands it before the calls around it (D114): its head left out, the `extend`s
     * it adds after what it is on (`deriveExpansion`, signatures only).
     */
    private func chainFrom(
        item: ItemId,
        chain: MacroCallChain,
        from: Int64,
        builder: MappedTextBuilder,
        children: ArrayList<MacroChild>
    ): Bool {
        let calls = chain.calls
        var start = calls[from].syntax.textRange.start
        let derived = ArrayList<(Expansion, TextRange)>()
        let written =
            {
                =>
                for (i in 0..derived.size) {
                    let (expansion, head) = derived[derived.size - 1 - i]
                    builder
                        .paste(
                            MappedText(
                                "\n" + expansion.text,
                                [
                                    MappedSpan(
                                        TextRange(0, expansion.text.size + 1),
                                        SpanOrigin.FromCall
                                    )
                                ]
                            ),
                            head
                        )
                }
                true
            }
        for (i in from..calls.size) {
            let key = MacroCallKey(item.toString(), chain.base + i)
            if (let Some(inner) <- served.get(key)) {
                let output = macroOutputOf(db, inner.call) ?? return false
                if (let Some(expansion) <- output.expansion) {
                    builder.copy(TextRange(start, calls[i].syntax.textRange.start))
                    builder.paste(expansion, macroHeadOf(calls[i]))
                    // what the calls nested in it set as well, as cjc gives an outer call every call inside it
                    children.add(all: request(inner).map { one => one.children } ?? [])
                    children.add(MacroChild(inner.definition.name, output.items))
                    return written()
                }
                // a run of std's macro that failed: cjls's own expansion stands in the input, as beside the item
                if (!inner.definition.isStd) {
                    return false
                }
            }
            if (chain.onItem && let Some(expansion) <- derivedBy(item, i, calls[i])) {
                let head = headOf(calls[i])
                builder.copy(TextRange(start, head.start))
                derived.add((expansion, head))
                // from what follows the head: the next call, or the declaration
                start =
                    calls.get(i + 1).map { next => next.syntax.textRange.start } ??
                        calls[i].decl().map { decl => decl.syntax.textRange.start } ?? head.end
            }
        }
        let last = calls[calls.size - 1]
        match (last.decl()) {
            case Some(decl) =>
                builder.copy(TextRange(start, decl.syntax.textRange.start))
                declaration(item, decl.syntax, builder, children) && written()
            case None => bodyInput(TextRange(start, last.syntax.textRange.end), builder, children)
        }
    }

    /**
     * What `call`, at `index` on `item`, adds after its declaration if it is std's `@Derive`.
     */
    private func derivedBy(item: ItemId, index: Int64, call: MacroExpandDecl): ?Expansion {
        let resolution =
            macrosOf(db, DefId(db, ItemFile.Source(file), item)).get(index) ?? return None
        match (stdMacroOf(db, resolution)) {
            case Some(DeriveMacro) => ()
            case _ => return None
        }
        let decl = ids.node(item, root).flatMap { node => Decl.cast(node) } ?? return None
        deriveExpansion(decl, call)
    }

    /**
     * Writes the declaration `node` of `item`: each chain of macro calls in it as its calls, those on its parameters
     * (D119) and, for each member, those on the member, or on its parameters when it has none of its own.
     */
    private func declaration(
        item: ItemId,
        node: CjSyntaxNode,
        builder: MappedTextBuilder,
        children: ArrayList<MacroChild>
    ): Bool {
        let chains = ArrayList<(ItemId, MacroCallChain)>()
        for (chain in macroCallChainsOf(node) where !chain.onItem) {
            chains.add((item, chain))
        }
        for (member in membersOf(item) where hasMacroCalls(member)) {
            let memberNode = ids.node(member.id, root) ?? continue
            // the member's own calls reach its parameters' through its declaration
            for (
                chain in macroCallChainsOf(memberNode) where chain.onItem ==
                    !member.macros.isEmpty()
            ) {
                chains.add((member.id, chain))
            }
        }
        sort(
            chains,
            by: {
                a, b =>
                a[1].calls[0].syntax.textRange.start.compare(b[1].calls[0].syntax.textRange.start)
            }
        )
        var at = node.textRange.start
        for ((owner, chain) in chains) {
            let range = chain.calls[0].syntax.textRange
            if (range.start < at || range.end > node.textRange.end) {
                continue
            }
            if (!bodyInput(TextRange(at, range.start), builder, children)) {
                return false
            }
            if (!chainFrom(owner, chain, 0, builder, children)) {
                return false
            }
            at = range.end
        }
        bodyInput(TextRange(at, node.textRange.end), builder, children)
    }

    private func membersOf(item: ItemId): Array<Item> {
        for (one in tree.items where one.id == item) {
            return one.members
        }
        []
    }

    /**
     * The names of the macros called around the call at `index` on `item`, under the top-level item `top`, outermost
     * first: for a call on a parameter (D119), those on the item and then the outer ones on the parameter.
     */
    private func parentsOf(top: ItemId, item: ItemId, index: Int64): Array<String> {
        let names = ArrayList<String>()
        for (one in tree.items where one.id == top) {
            if (top == item) {
                names.add(all: macrosAround(one, index))
            } else {
                names.add(all: one.macros.map { name => lastSegmentOf(name) })
                for (member in one.members where member.id == item) {
                    names.add(all: macrosAround(member, index))
                }
            }
        }
        names.toArray()
    }

    /**
     * The macros called around the call at `index` of `item`, outermost first: those before it among the item's own,
     * or all of the item's own and then those before it on its parameter.
     */
    private func macrosAround(item: Item, index: Int64): Array<String> {
        if (index < item.macros.size) {
            return item.macros[0..index].map { name => lastSegmentOf(name) }
        }
        let names = ArrayList<String>(item.macros.map { name => lastSegmentOf(name) })
        var base = item.macros.size
        for (chain in item.paramMacros) {
            if (index < base + chain.size) {
                names.add(all: chain[0..index - base].map { name => lastSegmentOf(name) })
                break
            }
            base += chain.size
        }
        names.toArray()
    }
}

/**
 * The unqualified macro name used in parent contexts.
 */
func lastSegmentOf(path: String): String {
    let segments = path.split(".")
    segments[segments.size - 1]
}

/**
 * What tells one request from another: everything the macro reads, and the library it runs from.
 */
func fingerprintOf(
    definition: ServerMacro,
    library: Int64,
    attrs: ?MappedText,
    input: MappedText,
    parents: Array<String>,
    children: ArrayList<MacroChild>
): Int64 {
    let text = StringBuilder()
    text.append(definition.name)
    text.append("\u{0}")
    text.append(library)
    text.append("\u{0}")
    text.append(attrs.map { one => "[${one.text}]" } ?? "")
    text.append("\u{0}")
    text.append(input.text)
    for (parent in parents) {
        text.append("\u{0}^")
        text.append(parent)
    }
    for (child in children) {
        text.append("\u{0}v")
        text.append(child.name)
        for (item in child.items) {
            text.append("\u{1}")
            text.append(item.toString())
        }
    }
    text.toString().hashCode()
}
