package loupe.hir

import std.collection.*
import std.deriving.*
import std.sort.*
import ginkgo.TextRange
import cjsyntax.{CjSyntaxNode, SyntaxKind}
import cjsyntax.ast.{AnyHasName, Decl, MacroExpandDecl}
import calca.*
import calca.macros.*
import loupe.db.*
import loupe.syntax.parse

/**
 * A macro declared in a package of the workspace, which the macro server runs (#176): the package and the macro's
 * name.
 */
@Derive[Equatable]
public struct WorkspaceMacro {
    public WorkspaceMacro(public let pkg: Package, public let name: String) {}
}

/**
 * The macro of the workspace `resolution`, of a macro's name, is: one declared in a source package.
 */
func workspaceMacroOf(db: AnalysisDatabase, resolution: Resolution): ?WorkspaceMacro {
    let (_, name) = macroPathOf(db, resolution) ?? return None
    let decl = macroDeclsOf(resolution).get(0) ?? return None
    match (packageRefOf(db, decl)) {
        case Some(Source(pkg)) => WorkspaceMacro(pkg, name)
        case _ => None
    }
}

/**
 * A call of a workspace macro in a file: the call, its macro, the top-level item it is under, and whether its
 * expansion is the one the analysis reads: the outermost such call on a top-level item, whose output replaces it as
 * cjc's does. The others are expanded only into the input of the calls around them.
 */
@Derive[Equatable]
public struct WorkspaceCall {
    public WorkspaceCall(
        public let call: MacroCallId,
        public let definition: WorkspaceMacro,
        public let top: ItemId,
        public let read: Bool
    ) {}
}

/**
 * The calls of workspace macros in `file`, in the order cjc expands them: under a top-level item, its members' calls,
 * then its own, each item's the calls in it (D117), then those on its parameters (D119) and then on itself, innermost
 * first. A call on a member whose type has no workspace macro, or on a parameter, is expanded and read by nothing of
 * its own (#176), and so far one in an item too (#369).
 */
@CalcaTracked
public func workspaceCalls(db: AnalysisDatabase, file: SourceFile): Array<WorkspaceCall> {
    let found = ArrayList<WorkspaceCall>()
    let inItems = HashMap<ItemId, ArrayList<BodyMacroCall>>()
    for (one in bodyMacroCalls(db, file)) {
        let calls = inItems.get(one.item) ?? ArrayList<BodyMacroCall>()
        calls.add(one)
        inItems[one.item] = calls
    }
    let pkg = packageOfFile(db, file)
    let addInItem = {
        item: ItemId, top: ItemId =>
        for (one in inItems.get(item) ?? ArrayList<BodyMacroCall>()) {
            let owner = pkg ?? break
            let path = one.name.split(".")
            let definition = workspaceMacroOf(db, resolveMacroPath(db, owner, file, path)[path.size - 1]) ?? continue
            found.add(WorkspaceCall(MacroCallId(db, file, item, one.index, Some(one.name)), definition, top, false))
        }
    }
    for (item in itemTree(db, file).items) {
        for (member in item.members) {
            addInItem(member.id, item.id)
            if (hasMacroCalls(member)) {
                addWorkspaceCalls(db, file, member, item.id, false, found)
            }
        }
        addInItem(item.id, item.id)
        if (hasMacroCalls(item)) {
            addWorkspaceCalls(db, file, item, item.id, true, found)
        }
    }
    found.toArray()
}

/**
 * Whether a macro is called on `item` or on one of its parameters.
 */
func hasMacroCalls(item: Item): Bool {
    !item.macros.isEmpty() || !item.paramMacros.isEmpty()
}

func addWorkspaceCalls(db: AnalysisDatabase, file: SourceFile, item: Item, top: ItemId, isTop: Bool,
    found: ArrayList<WorkspaceCall>): Unit {
    let resolutions = macrosOf(db, DefId(db, ItemFile.Source(file), item.id))
    // the chains, by the range of their indices: the item's own first, then its parameters'
    let chains = ArrayList<(Int64, Int64)>([(0, item.macros.size)])
    for (one in item.paramMacros) {
        let base = chains[chains.size - 1][1]
        chains.add((base, base + one.size))
    }
    // the parameters' chains in their order, then the item's own
    for (c in (1..chains.size).iterator().concat([0].iterator())) {
        let (base, end) = chains[c]
        let calls = ArrayList<(Int64, WorkspaceMacro)>()
        for (i in base..end) {
            // none for an item resolution does not see (`macrosOf`: a file of no package, an inactive item)
            let resolution = resolutions.get(i) ?? continue
            if (let Some(definition) <- workspaceMacroOf(db, resolution)) {
                calls.add((i, definition))
            }
        }
        for (j in calls.size - 1..=0 : -1) {
            let (index, definition) = calls[j]
            found.add(WorkspaceCall(MacroCallId(db, file, item.id, index, None), definition, top,
                isTop && c == 0 && j == 0))
        }
    }
}

/**
 * How `call` is keyed among the outputs of its file: what names it across revisions, where a `MacroCallId` may be
 * collected (D18); `macroCallOf` goes back.
 */
public func macroCallKeyOf(db: AnalysisDatabase, call: MacroCallId): MacroCallKey {
    MacroCallKey(call.item(db).toString(), call.index(db), inBody: call.inBody(db))
}

/**
 * What the macro server last answered for `call`, if it did.
 */
public func macroOutputOf(db: AnalysisDatabase, call: MacroCallId): ?MacroOutput {
    call.file(db).macroOutputs(db).get(macroCallKeyOf(db, call))
}

/**
 * The last expansion of `call` by the macro server that succeeded, if there is one.
 */
func serverExpansionOf(db: AnalysisDatabase, call: MacroCallId): ?MappedText {
    macroOutputOf(db, call).flatMap {output => output.expansion}
}

/**
 * Sets what the macro server answered for each call, in one revision; a run that failed keeps the expansion of the last
 * that succeeded (`MacroOutput.after`).
 *
 * @throws IllegalStateException - if `db` is a snapshot, or a query is running on it
 */
public func setMacroOutputs(db: AnalysisDatabase, answers: Array<(MacroCallId, MacroOutput)>): Unit {
    setMacroOutputsByKey(db, answers.map {answer => (answer[0].file(db), macroCallKeyOf(db, answer[0]), answer[1])})
}

/**
 * `setMacroOutputs` of calls by their file and key, which a thread holding them across revisions keeps instead of a
 * `MacroCallId` (D18): what it answered is set even if the call is gone, and read by nothing then.
 *
 * @throws IllegalStateException - if `db` is a snapshot, or a query is running on it
 */
public func setMacroOutputsByKey(db: AnalysisDatabase, answers: Array<(SourceFile, MacroCallKey, MacroOutput)>): Unit {
    let byFile = HashMap<SourceFile, MacroOutputs>()
    for ((file, key, output) in answers) {
        let outputs = byFile.get(file) ?? file.macroOutputs(db)
        byFile[file] = outputs.withOutput(key, output)
    }
    db.batch {
        for ((file, outputs) in byFile) {
            file.setMacroOutputs(db).to(outputs)
        }
    }
}

/**
 * What another macro call nested in a call's input set (`setItem`), which its macro reads with `getChildMessages`.
 */
@Derive[Equatable]
public struct MacroChild {
    public MacroChild(public let name: String, public let items: Array<MacroItem>) {}
}

/**
 * What the macro server is asked to expand a call of a workspace macro with (#176): the macro; the text of its
 * attribute (`None` for a macro called without one) and of its input, where the calls nested in it are their outputs,
 * as cjc expands them innermost first; the names of the macro calls around it, outermost first; what the calls nested
 * in it set; the fingerprint of all of it; and whether the output stored for the call answered this request.
 */
@Derive[Equatable]
public struct MacroRequest {
    public MacroRequest(
        public let call: MacroCallId,
        public let definition: WorkspaceMacro,
        public let attrs: ?MappedText,
        public let input: MappedText,
        public let parents: Array<String>,
        public let children: Array<MacroChild>,
        public let fingerprint: Int64,
        public let current: Bool
    ) {}
}

/**
 * The requests for the calls of workspace macros in `file` (`workspaceCalls`), in their order: those whose input can
 * be written, each call nested in it having an expansion.
 */
@CalcaTracked
public func macroRequests(db: AnalysisDatabase, file: SourceFile): Array<MacroRequest> {
    let calls = workspaceCalls(db, file)
    if (calls.isEmpty()) {
        return []
    }
    let composer = MacroInputComposer(calls, db, file)
    calls |> filterMap {call: WorkspaceCall => composer.request(call)} |> collectArray
}

/**
 * The requests of `file` whose call has no output for them yet: what to send to the macro server.
 */
public func pendingMacroRequests(db: AnalysisDatabase, file: SourceFile): Array<MacroRequest> {
    macroRequests(db, file).filter {request => !request.current}
}

/**
 * The calls of workspace macros in `file` whose expansion the analysis reads, and have one. A file the macro server
 * answered nothing for runs no query for it.
 */
func readWorkspaceCallsOf(db: AnalysisDatabase, file: SourceFile): Array<MacroCallId> {
    if (file.macroOutputs(db).size == 0) {
        return []
    }
    workspaceCalls(db, file) |> filter {one: WorkspaceCall => one.read} |> map {one: WorkspaceCall => one.call} |>
        filter {call: MacroCallId => serverExpansionOf(db, call).isSome()} |> collectArray
}

/**
 * The expansion of `call` if it is a call of a workspace macro the analysis reads, which replaces its item.
 */
func workspaceExpansionOf(db: AnalysisDatabase, call: MacroCallId): ?Expansion {
    if (!workspaceCalls(db, call.file(db)).iterator().any {one => one.read && one.call == call}) {
        return None
    }
    let output = serverExpansionOf(db, call) ?? return None
    Expansion(output.text, [], replaces: true, spans: output.spans)
}

/**
 * Whether `def`, a declaration of a source file or a member of one, is under a top-level item a call of a workspace
 * macro the analysis reads replaces: what its macros add is read from that expansion.
 */
func isReplacedByWorkspaceExpansion(db: AnalysisDatabase, def: DefId): Bool {
    let file = match (def.file(db)) {
        case Source(file) => file
        case _ => return false
    }
    if (file.macroOutputs(db).size == 0) {
        return false
    }
    let top = (parentOf(db, def) ?? def).item(db)
    workspaceCalls(db, file).iterator().any {
        one => one.read && one.top == top && serverExpansionOf(db, one.call).isSome()
    }
}

/**
 * What `def`, a declaration of a source file or a member of one under a top-level item a workspace macro's expansion
 * replaces, became in that expansion: its declaration whose name the macro copied from `def`'s (#176). `None` if no
 * expansion the analysis reads replaces it, or the macro dropped or renamed it.
 */
public func expandedDeclOf(db: AnalysisDatabase, def: DefId): ?DefId {
    if (!isReplacedByWorkspaceExpansion(db, def)) {
        return None
    }
    let file = match (def.file(db)) {
        case Source(file) => file
        case _ => return None
    }
    let top = (parentOf(db, def) ?? def).item(db)
    let call = (workspaceCalls(db, file).iterator().filter {one => one.read && one.top == top}.next() ?? return None).call
    let node = itemIdMap(db, file).node(def.item(db), parse(db, file).syntaxNode()) ?? return None
    let name = AnyHasName.cast(node).flatMap {it => it.name()}?.syntax.textRange ?? return None
    let items = expansionItemTree(db, call).items |> flatMap {item: Item => [item].concat(item.members)} |>
        map {item: Item => item.id} |> collectArray
    let item = (items |> filter {id: ItemId => expansionOrigin(db, call, id).map {origin => origin[0]} == name} |> first) ?? return None
    DefId(db, ItemFile.Expansion(call), item)
}

/**
 * What a macro reported running a call of a file, where in the file: what its origin names in the source, else the
 * head of the call (`@` to the end of its attribute).
 */
@Derive[Equatable]
public struct MacroCallDiagnostic {
    public MacroCallDiagnostic(public let range: TextRange, public let severity: MacroSeverity,
        public let message: String) {}
}

/**
 * What the macros of the workspace reported running the calls of `file`, for the outputs that answered the request
 * as it stands: an older one's ranges may no longer be where its call is.
 */
@CalcaTracked
public func macroDiagnostics(db: AnalysisDatabase, file: SourceFile): Array<MacroCallDiagnostic> {
    if (file.macroOutputs(db).size == 0) {
        return []
    }
    let root = parse(db, file).syntaxNode()
    let ids = itemIdMap(db, file)
    let size = file.text(db).size
    let current = HashSet<MacroCallId>()
    for (request in macroRequests(db, file) where request.current) {
        current.add(request.call)
    }
    let found = ArrayList<MacroCallDiagnostic>()
    for (one in workspaceCalls(db, file) where current.contains(one.call)) {
        let output = macroOutputOf(db, one.call) ?? continue
        if (output.diagnostics.isEmpty()) {
            continue
        }
        let head = if (one.call.inBody(db).isSome()) {
            (bodyCallSyntaxOf(db, one.call) ?? continue).head()
        } else {
            let node = ids.node(one.call.item(db), root) ?? continue
            macroHeadOf(macroCallAt(node, one.call.index(db)) ?? continue)
        }
        let anchor = anchorOf(ids, root, one.top) ?? continue
        for (diagnostic in output.diagnostics) {
            let range = match (diagnostic.origin) {
                case Some(FromSource(range)) where anchor + range.end <= size => TextRange(anchor + range.start,
                    anchor + range.end)
                case _ => head
            }
            let message = if (diagnostic.hint.isEmpty()) {
                diagnostic.message
            } else {
                "${diagnostic.message}: ${diagnostic.hint}"
            }
            found.add(MacroCallDiagnostic(range, diagnostic.severity, message))
        }
    }
    found.toArray()
}

/**
 * Where the top-level item `top` of `root` starts: its outermost macro call's `@`, which the origins of its macro
 * calls' text are relative to.
 */
func anchorOf(ids: ItemIdMap, root: CjSyntaxNode, top: ItemId): ?Int64 {
    let node = ids.node(top, root) ?? return None
    (macroCallsOf(node).get(0)?.syntax ?? node).textRange.start
}

/**
 * The range from `call`'s `@` to the end of its attribute, or of its name: where what its macro wrote is said to come
 * from.
 */
func macroHeadOf(call: MacroExpandDecl): TextRange {
    let start = call.syntax.textRange.start
    if (let Some(attr) <- call.macroAttr()) {
        return TextRange(start, attr.syntax.textRange.end)
    }
    let names = call.nameRefs() |> map {name => name.syntax.textRange.end} |> collectArray
    TextRange(start, names.get(names.size - 1) ?? (call.atToken()?.textRange.end ?? start))
}

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
        spans.add(MappedSpan(TextRange.at(size, range.len), SpanOrigin.FromSource(TextRange.at(range.start - anchor,
            range.len))))
        size += range.len
    }

    /**
     * Appends the output of the call whose head is `head`: what its macro wrote is said to come from there.
     */
    func paste(output: MappedText, head: TextRange): Unit {
        text.append(output.text)
        for (span in output.spans) {
            let origin = match (span.origin) {
                case FromCall => SpanOrigin.FromSource(TextRange(head.start - anchor, head.end - anchor))
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
    let start = match (node.firstToken()) {
        case Some(first) where first.kind == open => first.textRange.end
        case _ => node.textRange.start
    }
    let end = match (node.lastToken()) {
        case Some(last) where last.kind == close && last.textRange.start >= start => last.textRange.start
        case _ => node.textRange.end
    }
    TextRange(start, end)
}

/**
 * Writes the requests of a file's calls of workspace macros: their input is the text of the source, where each call
 * nested in it is its output (the last that succeeded).
 */
class MacroInputComposer {
    private let root: CjSyntaxNode
    private let ids: ItemIdMap
    private let tree: ItemTree
    private let source: String
    private let workspace = HashMap<MacroCallKey, WorkspaceCall>()

    MacroInputComposer(calls: Array<WorkspaceCall>, private let db: AnalysisDatabase, private let file: SourceFile) {
        root = parse(db, file).syntaxNode()
        ids = itemIdMap(db, file)
        tree = itemTree(db, file)
        source = file.text(db).toString()
        for (one in calls) {
            workspace[macroCallKeyOf(db, one.call)] = one
        }
    }

    /**
     * The request for `call`; `None` if a call nested in its input has no expansion, or its item is not there. The
     * input of a call on a parameter (D119) is the parameter, as cjc gives it.
     */
    func request(call: WorkspaceCall): ?MacroRequest {
        if (call.call.inBody(db).isSome()) {
            return requestInItem(call)
        }
        let item = call.call.item(db)
        let index = call.call.index(db)
        let anchor = anchorOf(ids, root, call.top) ?? return None
        let node = ids.node(item, root) ?? return None
        let (chain, position) = macroCallChainAt(node, index) ?? return None
        let macroCall = chain.calls[position]
        let attrs = macroCall.macroAttr().map {
            attr =>
            let builder = MappedTextBuilder(source, anchor)
            builder.copy(innerRangeOf(attr.syntax, SyntaxKind.LBracket, SyntaxKind.RBracket))
            builder.build()
        }
        let builder = MappedTextBuilder(source, anchor)
        let children = ArrayList<MacroChild>()
        let ready = if (position + 1 < chain.calls.size) {
            chainFrom(item, chain, position + 1, builder, children)
        } else if (let Some(decl) <- macroCall.decl()) {
            declaration(item, decl.syntax, builder, children)
        } else if (let Some(param) <- macroCall.param()) {
            builder.copy(param.syntax.textRange)
            true
        } else if (let Some(args) <- macroCall.macroArgs()) {
            builder.copy(innerRangeOf(args.syntax, SyntaxKind.LParen, SyntaxKind.RParen))
            true
        } else {
            true
        }
        if (!ready) {
            return None
        }
        let input = builder.build()
        let parents = parentsOf(call.top, item, index)
        let fingerprint = fingerprintOf(call.definition, call.definition.pkg.macroLibrary(db), attrs, input, parents,
            children)
        let current = macroOutputOf(db, call.call)?.fingerprint == fingerprint
        MacroRequest(call.call, call.definition, attrs, input, parents, children.toArray(), fingerprint, current)
    }

    /**
     * The request for `call`, a call in an item (D117): its input what is between its parentheses, or the local
     * declaration it is on; its parents the macros on the items around it, then the calls in the item whose input it
     * is in. `None` while another call is in its input, which cjc expands first (#371), or once it is gone.
     */
    private func requestInItem(call: WorkspaceCall): ?MacroRequest {
        let found = bodyMacroCallOf(db, call.call) ?? return None
        if (found.holdsCalls) {
            return None
        }
        let syntax = bodyCallSyntaxOf(db, call.call) ?? return None
        let anchor = anchorOf(ids, root, call.top) ?? return None
        let attrs = syntax.macroAttr().map {
            attr =>
            let builder = MappedTextBuilder(source, anchor)
            builder.copy(innerRangeOf(attr.syntax, SyntaxKind.LBracket, SyntaxKind.RBracket))
            builder.build()
        }
        let builder = MappedTextBuilder(source, anchor)
        match ((syntax.macroArgs(), syntax.rest())) {
            case (Some(args), _) => builder.copy(innerRangeOf(args.syntax, SyntaxKind.LParen, SyntaxKind.RParen))
            case (None, Some(rest)) => builder.copy(rest.textRange)
            case _ => ()
        }
        let input = builder.build()
        let item = call.call.item(db)
        let parents = parentsOf(call.top, item, macroCountOf(item)).concat(found.around)
        let children = ArrayList<MacroChild>()
        let fingerprint = fingerprintOf(call.definition, call.definition.pkg.macroLibrary(db), attrs, input, parents,
            children)
        let current = macroOutputOf(db, call.call)?.fingerprint == fingerprint
        MacroRequest(call.call, call.definition, attrs, input, parents, [], fingerprint, current)
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
     * on: up to the first call of a workspace macro the text of the source, then that call's output. Of std's
     * macros, which are not run here (#176), `@Derive` is expanded as cjc expands it before the calls around it: its
     * head left out, the `extend`s it adds after what it is on (`deriveExpansion`, signatures only); any other stays
     * as written.
     */
    private func chainFrom(item: ItemId, chain: MacroCallChain, from: Int64, builder: MappedTextBuilder,
        children: ArrayList<MacroChild>): Bool {
        let calls = chain.calls
        var start = calls[from].syntax.textRange.start
        let derived = ArrayList<(Expansion, TextRange)>()
        let written = {
            =>
            for (i in 0..derived.size) {
                let (expansion, head) = derived[derived.size - 1 - i]
                builder.paste(MappedText("\n" + expansion.text, [MappedSpan(TextRange(0, expansion.text.size + 1),
                    SpanOrigin.FromCall)]), head)
            }
            true
        }
        for (i in from..calls.size) {
            let key = MacroCallKey(item.toString(), chain.base + i)
            if (let Some(inner) <- workspace.get(key)) {
                builder.copy(TextRange(start, calls[i].syntax.textRange.start))
                let output = macroOutputOf(db, inner.call) ?? return false
                let expansion = output.expansion ?? return false
                builder.paste(expansion, macroHeadOf(calls[i]))
                // what the calls nested in it set as well, as cjc gives an outer call every call inside it
                children.add(all: request(inner).map {one => one.children} ?? [])
                children.add(MacroChild(inner.definition.name, output.items))
                return written()
            }
            if (chain.onItem && let Some(expansion) <- derivedBy(item, i, calls[i])) {
                let head = headOf(calls[i])
                builder.copy(TextRange(start, head.start))
                derived.add((expansion, head))
                // from what follows the head: the next call, or the declaration
                start = calls.get(i + 1).map {next => next.syntax.textRange.start} ??
                    calls[i].decl().map {decl => decl.syntax.textRange.start} ?? head.end
            }
        }
        let last = calls[calls.size - 1]
        match (last.decl()) {
            case Some(decl) =>
                builder.copy(TextRange(start, decl.syntax.textRange.start))
                declaration(item, decl.syntax, builder, children) && written()
            case None =>
                builder.copy(TextRange(start, last.syntax.textRange.end))
                true
        }
    }

    /**
     * What `call`, at `index` on `item`, adds after its declaration if it is std's `@Derive`.
     */
    private func derivedBy(item: ItemId, index: Int64, call: MacroExpandDecl): ?Expansion {
        let resolution = macrosOf(db, DefId(db, ItemFile.Source(file), item)).get(index) ?? return None
        match (stdMacroOf(db, resolution)) {
            case Some(DeriveMacro) => ()
            case _ => return None
        }
        let decl = ids.node(item, root).flatMap {node => Decl.cast(node)} ?? return None
        deriveExpansion(decl, call)
    }

    /**
     * Writes the declaration `node` of `item`: each chain of macro calls in it as its calls, those on its parameters
     * (D119) and, for each member, those on the member, or on its parameters when it has none of its own.
     */
    private func declaration(item: ItemId, node: CjSyntaxNode, builder: MappedTextBuilder,
        children: ArrayList<MacroChild>): Bool {
        let chains = ArrayList<(ItemId, MacroCallChain)>()
        for (chain in macroCallChainsOf(node) where !chain.onItem) {
            chains.add((item, chain))
        }
        for (member in membersOf(item) where hasMacroCalls(member)) {
            let memberNode = ids.node(member.id, root) ?? continue
            // the member's own calls reach its parameters' through its declaration
            for (chain in macroCallChainsOf(memberNode) where chain.onItem == !member.macros.isEmpty()) {
                chains.add((member.id, chain))
            }
        }
        sort(chains, by: {
            a: (ItemId, MacroCallChain), b: (ItemId, MacroCallChain) =>
            a[1].calls[0].syntax.textRange.start.compare(b[1].calls[0].syntax.textRange.start)
        })
        var at = node.textRange.start
        for ((owner, chain) in chains) {
            let range = chain.calls[0].syntax.textRange
            if (range.start < at || range.end > node.textRange.end) {
                continue
            }
            builder.copy(TextRange(at, range.start))
            if (!chainFrom(owner, chain, 0, builder, children)) {
                return false
            }
            at = range.end
        }
        builder.copy(TextRange(at, node.textRange.end))
        true
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
                names.add(all: one.macros.map {name => lastSegmentOf(name)})
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
            return item.macros[0..index].map {name => lastSegmentOf(name)}
        }
        let names = ArrayList<String>(item.macros.map {name => lastSegmentOf(name)})
        var base = item.macros.size
        for (chain in item.paramMacros) {
            if (index < base + chain.size) {
                names.add(all: chain[0..index - base].map {name => lastSegmentOf(name)})
                break
            }
            base += chain.size
        }
        names.toArray()
    }
}

func lastSegmentOf(path: String): String {
    let segments = path.split(".")
    segments[segments.size - 1]
}

/**
 * What tells one request from another: everything the macro reads, and the library it runs from.
 */
func fingerprintOf(definition: WorkspaceMacro, library: Int64, attrs: ?MappedText, input: MappedText,
    parents: Array<String>, children: ArrayList<MacroChild>): Int64 {
    let text = StringBuilder()
    text.append(definition.name)
    text.append("\u{0}")
    text.append(library)
    text.append("\u{0}")
    text.append(attrs.map {one => "[${one.text}]"} ?? "")
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
