package loupe.hir

import std.collection.*
import std.deriving.*
import ginkgo.TextRange
import cjsyntax.CjSyntaxNode
import cjsyntax.ast.MacroExpandDecl
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
 * then its own, each item's innermost call first. A call on a member whose type has no workspace macro is expanded
 * and read by nothing (#176).
 */
@CalcaTracked
public func workspaceCalls(db: AnalysisDatabase, file: SourceFile): Array<WorkspaceCall> {
    let found = ArrayList<WorkspaceCall>()
    for (item in itemTree(db, file).items) {
        for (member in item.members where !member.macros.isEmpty()) {
            addWorkspaceCalls(db, file, member, item.id, false, found)
        }
        if (!item.macros.isEmpty()) {
            addWorkspaceCalls(db, file, item, item.id, true, found)
        }
    }
    found.toArray()
}

func addWorkspaceCalls(db: AnalysisDatabase, file: SourceFile, item: Item, top: ItemId, isTop: Bool,
    found: ArrayList<WorkspaceCall>): Unit {
    let resolutions = macrosOf(db, DefId(db, ItemFile.Source(file), item.id))
    let calls = ArrayList<(Int64, WorkspaceMacro)>()
    for (i in 0..resolutions.size) {
        if (let Some(definition) <- workspaceMacroOf(db, resolutions[i])) {
            calls.add((i, definition))
        }
    }
    for (j in calls.size - 1..=0 : -1) {
        let (index, definition) = calls[j]
        found.add(WorkspaceCall(MacroCallId(db, file, item.id, index), definition, top, isTop && j == 0))
    }
}

/**
 * How `call` is keyed among the outputs of its file: what names it across revisions, where a `MacroCallId` may be
 * collected (D18); `macroCallOf` goes back.
 */
public func macroCallKeyOf(db: AnalysisDatabase, call: MacroCallId): MacroCallKey {
    MacroCallKey(call.item(db).toString(), call.index(db))
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
    let byFile = HashMap<SourceFile, MacroOutputs>()
    for ((call, output) in answers) {
        let file = call.file(db)
        let outputs = byFile.get(file) ?? file.macroOutputs(db)
        byFile[file] = outputs.withOutput(macroCallKeyOf(db, call), output)
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
     * The request for `call`; `None` if a call nested in its input has no expansion, or its item is not there.
     */
    func request(call: WorkspaceCall): ?MacroRequest {
        let item = call.call.item(db)
        let index = call.call.index(db)
        let anchor = anchorOf(ids, root, call.top) ?? return None
        let node = ids.node(item, root) ?? return None
        let chain = macroCallsOf(node)
        let macroCall = chain.get(index) ?? return None
        let attrs = macroCall.macroAttr().map {
            attr =>
            let builder = MappedTextBuilder(source, anchor)
            let open = attr.lBracketToken()?.textRange.end ?? attr.syntax.textRange.start
            let close = attr.rBracketToken()?.textRange.start ?? attr.syntax.textRange.end
            builder.copy(TextRange(open, close))
            builder.build()
        }
        let builder = MappedTextBuilder(source, anchor)
        let children = ArrayList<MacroChild>()
        let ready = if (index + 1 < chain.size) {
            chainFrom(item, chain, index + 1, builder, children)
        } else if (let Some(decl) <- macroCall.decl()) {
            declaration(item, decl.syntax, builder, children)
        } else if (let Some(args) <- macroCall.macroArgs()) {
            let open = args.lParenToken()?.textRange.end ?? args.syntax.textRange.start
            let close = args.rParenToken()?.textRange.start ?? args.syntax.textRange.end
            builder.copy(TextRange(open, close))
            true
        } else {
            true
        }
        if (!ready) {
            return None
        }
        let input = builder.build()
        let parents = parentsOf(call.top, item, index)
        let fingerprint = fingerprintOf(call.definition, attrs, input, parents, children)
        let current = macroOutputOf(db, call.call)?.fingerprint == fingerprint
        MacroRequest(call.call, call.definition, attrs, input, parents, children.toArray(), fingerprint, current)
    }

    /**
     * Writes the calls `chain` from `from` on, on `item`, and its declaration: up to the first call of a workspace
     * macro the text of the source (a macro of std is not expanded here, #176), then that call's output.
     */
    private func chainFrom(item: ItemId, chain: Array<MacroExpandDecl>, from: Int64, builder: MappedTextBuilder,
        children: ArrayList<MacroChild>): Bool {
        let start = chain[from].syntax.textRange.start
        for (i in from..chain.size) {
            let key = MacroCallKey(item.toString(), i)
            if (let Some(inner) <- workspace.get(key)) {
                builder.copy(TextRange(start, chain[i].syntax.textRange.start))
                let output = macroOutputOf(db, inner.call) ?? return false
                let expansion = output.expansion ?? return false
                builder.paste(expansion, macroHeadOf(chain[i]))
                children.add(MacroChild(inner.definition.name, output.items))
                return true
            }
        }
        let last = chain[chain.size - 1]
        match (last.decl()) {
            case Some(decl) =>
                builder.copy(TextRange(start, decl.syntax.textRange.start))
                declaration(item, decl.syntax, builder, children)
            case None =>
                builder.copy(TextRange(start, last.syntax.textRange.end))
                true
        }
    }

    /**
     * Writes the declaration `node` of `item`, each member with macros called on it as its calls.
     */
    private func declaration(item: ItemId, node: CjSyntaxNode, builder: MappedTextBuilder,
        children: ArrayList<MacroChild>): Bool {
        let members = membersOf(item).filter {member => !member.macros.isEmpty()} |> filterMap {
            member: Item => ids.node(member.id, root).map {one => (member.id, macroCallsOf(one))}
        } |> filter {pair: (ItemId, Array<MacroExpandDecl>) => !pair[1].isEmpty()} |> collectArray
        var at = node.textRange.start
        for ((member, chain) in members) {
            let range = chain[0].syntax.textRange
            if (range.start < at || range.end > node.textRange.end) {
                continue
            }
            builder.copy(TextRange(at, range.start))
            if (!chainFrom(member, chain, 0, builder, children)) {
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
     * first.
     */
    private func parentsOf(top: ItemId, item: ItemId, index: Int64): Array<String> {
        let names = ArrayList<String>()
        for (one in tree.items where one.id == top) {
            if (top == item) {
                names.add(all: one.macros[0..index].map {name => lastSegmentOf(name)})
            } else {
                names.add(all: one.macros.map {name => lastSegmentOf(name)})
                for (member in one.members where member.id == item) {
                    names.add(all: member.macros[0..index].map {name => lastSegmentOf(name)})
                }
            }
        }
        names.toArray()
    }
}

func lastSegmentOf(path: String): String {
    let segments = path.split(".")
    segments[segments.size - 1]
}

/**
 * What tells one request from another: everything the macro reads.
 */
func fingerprintOf(definition: WorkspaceMacro, attrs: ?MappedText, input: MappedText, parents: Array<String>,
    children: ArrayList<MacroChild>): Int64 {
    let text = StringBuilder()
    text.append(definition.name)
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
