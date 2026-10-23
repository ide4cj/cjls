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
 * Where a macro the macro server runs is declared (#176): a source package of the workspace, whose library cjls builds
 * (D104), or a package of std, whose library the SDK ships.
 */
@Derive[Equatable]
public enum MacroPackage {
    | WorkspacePackage(Package)
    | StdPackage(BinaryPackageFile)
}

/**
 * A macro the macro server runs: its package and its name.
 */
@Derive[Equatable]
public struct ServerMacro {
    public ServerMacro(public let pkg: MacroPackage, public let name: String) {}

    /**
     * The name of its package, which cjc names the macro's function by.
     */
    public func pkgName(db: AnalysisDatabase): String {
        match (pkg) {
            case WorkspacePackage(source) => source.name(db)
            case StdPackage(binary) => binary.name(db)
        }
    }

    /**
     * The stamp of the library it runs from: of the one cjls built, 0 for none yet (`Package.macroLibrary`); of std's,
     * its `.cjo`'s, which another SDK changes.
     */
    public func libraryStamp(db: AnalysisDatabase): Int64 {
        match (pkg) {
            case WorkspacePackage(source) => source.macroLibrary(db)
            case StdPackage(binary) => binaryStamp(db, binary)
        }
    }

    /**
     * Whether it is a macro of std.
     */
    public prop isStd: Bool {
        get() {
            match (pkg) {
                case StdPackage(_) => true
                case WorkspacePackage(_) => false
            }
        }
    }
}

/**
 * A hash of the bytes of `binary`.
 */
@CalcaTracked
func binaryStamp(db: AnalysisDatabase, binary: BinaryPackageFile): Int64 {
    var hasher = DefaultHasher()
    for (byte in binary.bytes(db)) {
        hasher.write(byte)
    }
    hasher.finish()
}

/**
 * The macro the server runs that `resolution`, of a macro's name, is: one declared in a source package, or in a
 * package of std.
 */
func serverMacroOf(db: AnalysisDatabase, resolution: Resolution): ?ServerMacro {
    let (_, name) = macroPathOf(db, resolution) ?? return None
    let decl = macroDeclsOf(resolution).get(0) ?? return None
    match (packageRefOf(db, decl)) {
        case Some(Source(pkg)) => ServerMacro(WorkspacePackage(pkg), name)
        case Some(Binary(binary)) where binary.binary(db) == "std" =>
            ServerMacro(StdPackage(binary), name)
        case _ => None
    }
}

/**
 * A call the macro server runs in a file: the call, its macro, the top-level item it is under, and whether its
 * expansion is the one the analysis reads: the outermost such call on a top-level item, whose output replaces it as
 * cjc's does. The others are expanded only into the input of the calls around them.
 */
@Derive[Equatable]
public struct ServerCall {
    public ServerCall(
        public let call: MacroCallId,
        public let definition: ServerMacro,
        public let top: ItemId,
        public let read: Bool
    ) {}
}

/**
 * The calls the macro server runs in `file`, in the order cjc expands them: under a top-level item, its members'
 * calls, then its own, each item's the calls in it (D117), then those on its parameters (D119) and then on itself,
 * innermost first. A call of std on a member is one only under an item with a call the server runs, whose input it is
 * part of, and in an item none so far; a call of the workspace on a member of a type with none, or on a parameter, is
 * expanded and read by nothing of its own (#176), and so far one in an item too (#369).
 */
@CalcaTracked
public func serverCalls(db: AnalysisDatabase, file: SourceFile): Array<ServerCall> {
    let found = ArrayList<ServerCall>()
    let inItems = HashMap<ItemId, ArrayList<BodyMacroCall>>()
    for (one in bodyMacroCalls(db, file)) {
        let calls = inItems.get(one.item) ?? ArrayList<BodyMacroCall>()
        calls.add(one)
        inItems[one.item] = calls
    }
    let pkg = packageOfFile(db, file)
    let addInItem =
        {
            item: ItemId, top: ItemId =>
            for (one in inItems.get(item) ?? ArrayList<BodyMacroCall>()) {
                let owner = pkg ?? break
                let path = one.name.split(".")
                let definition =
                    serverMacroOf(db, resolveMacroPath(db, owner, file, path)[path.size - 1]) ??
                        continue
                // std's, whose expansion nothing reads yet (#369), are not run
                if (definition.isStd) {
                    continue
                }
                found
                    .add(
                        ServerCall(
                            MacroCallId(db, file, item, one.index, Some(one.name)),
                            definition,
                            top,
                            false
                        )
                    )
            }
        }
    for (item in itemTree(db, file).items) {
        let own: Array<ServerCall> =
            if (hasMacroCalls(item)) {
                serverCallsOn(db, file, item, item.id, true)
            } else {
                []
            }
        // a call on the item itself, whose input the members' calls are part of; not one on its parameters alone
        let read = own.iterator().any { one => one.read }
        for (member in item.members) {
            addInItem(member.id, item.id)
            if (hasMacroCalls(member)) {
                found
                    .add(
                        all: serverCallsOn(db, file, member, item.id, false)
                            .filter { one => read || !one.definition.isStd }
                    )
            }
        }
        addInItem(item.id, item.id)
        found.add(all: own)
    }
    found.toArray()
}

/**
 * Whether a macro is called on `item` or on one of its parameters.
 */
func hasMacroCalls(item: Item): Bool {
    !item.macros.isEmpty() || !item.paramMacros.isEmpty()
}

/**
 * The calls the server runs on `item`, under the top-level item `top`: those on its parameters (D119), then its
 * own, innermost first.
 */
func serverCallsOn(
    db: AnalysisDatabase,
    file: SourceFile,
    item: Item,
    top: ItemId,
    isTop: Bool
): Array<ServerCall> {
    let resolutions = macrosOf(db, DefId(db, ItemFile.Source(file), item.id))
    // the chains, by the range of their indices: the item's own first, then its parameters'
    let chains = ArrayList<(Int64, Int64)>([(0, item.macros.size)])
    for (one in item.paramMacros) {
        let base = chains[chains.size - 1][1]
        chains.add((base, base + one.size))
    }
    let found = ArrayList<ServerCall>()
    // the parameters' chains in their order, then the item's own
    for (c in (1..chains.size).iterator().concat([0].iterator())) {
        let (base, end) = chains[c]
        let calls = ArrayList<(Int64, ServerMacro)>()
        for (i in base..end) {
            // none for an item resolution does not see (`macrosOf`: a file of no package, an inactive item)
            let resolution = resolutions.get(i) ?? continue
            if (let Some(definition) <- serverMacroOf(db, resolution)) {
                calls.add((i, definition))
            }
        }
        for (j in calls.size - 1..=0: -1) {
            let (index, definition) = calls[j]
            found
                .add(
                    ServerCall(
                        MacroCallId(db, file, item.id, index, None),
                        definition,
                        top,
                        isTop && c == 0 && j == 0
                    )
                )
        }
    }
    found.toArray()
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
    macroOutputOf(db, call).flatMap { output => output.expansion }
}

/**
 * Sets what the macro server answered for each call, in one revision; a run that failed keeps the expansion of the last
 * that succeeded (`MacroOutput.after`).
 *
 * @throws IllegalStateException - if `db` is a snapshot, or a query is running on it
 */
public func setMacroOutputs(
    db: AnalysisDatabase,
    answers: Array<(MacroCallId, MacroOutput)>
): Unit {
    setMacroOutputsByKey(
        db,
        answers.map { answer => (answer[0].file(db), macroCallKeyOf(db, answer[0]), answer[1]) }
    )
}

/**
 * `setMacroOutputs` of calls by their file and key, which a thread holding them across revisions keeps instead of a
 * `MacroCallId` (D18): what it answered is set even if the call is gone, and read by nothing then.
 *
 * @throws IllegalStateException - if `db` is a snapshot, or a query is running on it
 */
public func setMacroOutputsByKey(
    db: AnalysisDatabase,
    answers: Array<(SourceFile, MacroCallKey, MacroOutput)>
): Unit {
    let byFile = HashMap<SourceFile, MacroOutputs>()
    for ((file, key, output) in answers) {
        let outputs = byFile.get(file) ?? file.macroOutputs(db)
        byFile[file] = outputs.withOutput(key, output)
    }
    db
        .batch {
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
 * What the macro server is asked to expand a call with (#176): the macro; the text of its
 * attribute (`None` for a macro called without one) and of its input, where the calls nested in it are their outputs,
 * as cjc expands them innermost first; the names of the macro calls around it, outermost first; what the calls nested
 * in it set; the fingerprint of all of it; and whether the output stored for the call answered this request.
 */
@Derive[Equatable]
public struct MacroRequest {
    public MacroRequest(
        public let call: MacroCallId,
        public let definition: ServerMacro,
        public let attrs: ?MappedText,
        public let input: MappedText,
        public let parents: Array<String>,
        public let children: Array<MacroChild>,
        public let fingerprint: Int64,
        public let current: Bool
    ) {}
}

/**
 * The requests for the calls the macro server runs in `file` (`serverCalls`), in their order: those whose input can
 * be written, each call nested in it having an expansion.
 */
@CalcaTracked
public func macroRequests(db: AnalysisDatabase, file: SourceFile): Array<MacroRequest> {
    let calls = serverCalls(db, file)
    if (calls.isEmpty()) {
        return []
    }
    let composer = MacroInputComposer(calls, db, file)
    calls |> filterMap { call: ServerCall => composer.request(call) } |> collectArray
}

/**
 * The requests of `file` whose call has no output for them yet: what to send to the macro server.
 */
public func pendingMacroRequests(db: AnalysisDatabase, file: SourceFile): Array<MacroRequest> {
    // a file with no macro call, most of them, runs no query of its own: the host asks after every edit
    let calls =
        itemTree(db, file)
            .items
            .iterator()
            .any {
                item =>
                hasMacroCalls(item) ||
                    item.members.iterator().any { member => hasMacroCalls(member) }
            }
    // those in items (D117) found by their own walk, once the items have none
    if (!calls && bodyMacroCalls(db, file).isEmpty()) {
        return []
    }
    macroRequests(db, file).filter { request => !request.current }
}

/**
 * The calls the macro server runs in `file` whose expansion the analysis reads, and have one: each replaces its item,
 * read through that output alone (D132). A file the macro server answered nothing for runs no query for it.
 */
public func readServerCallsOf(db: AnalysisDatabase, file: SourceFile): Array<MacroCallId> {
    if (file.macroOutputs(db).size == 0) {
        return []
    }
    serverCalls(db, file) |> filter { one: ServerCall => one.read } |>
        map { one: ServerCall => one.call } |>
        filter { call: MacroCallId => serverExpansionOf(db, call).isSome() } |>
        collectArray
}

/**
 * The expansion of `call` if it is a call the macro server ran that the analysis reads, which replaces its item.
 */
func serverCallExpansionOf(db: AnalysisDatabase, call: MacroCallId): ?Expansion {
    if (!serverCalls(db, call.file(db)).iterator().any { one => one.read && one.call == call }) {
        return None
    }
    let output = serverExpansionOf(db, call) ?? return None
    Expansion(output.text, [], replaces: true, spans: output.spans)
}

/**
 * Whether `def`, a declaration of a source file or a member of one, is under a top-level item the output of a call
 * the server ran replaces, read by the analysis: what its macros add is read from that expansion.
 */
func isReplacedByServerExpansion(db: AnalysisDatabase, def: DefId): Bool {
    let file =
        match (def.file(db)) {
            case Source(file) => file
            case _ => return false
        }
    if (file.macroOutputs(db).size == 0) {
        return false
    }
    let top = (parentOf(db, def) ?? def).item(db)
    serverCalls(db, file)
        .iterator()
        .any { one => one.read && one.top == top && serverExpansionOf(db, one.call).isSome() }
}

/**
 * What `def`, a declaration of a source file or a member of one under a top-level item an expansion the server made
 * replaces, became in that expansion: its declaration whose name the macro copied from `def`'s (#176). `None` if no
 * expansion the analysis reads replaces it, or the macro dropped or renamed it.
 */
public func expandedDeclOf(db: AnalysisDatabase, def: DefId): ?DefId {
    if (!isReplacedByServerExpansion(db, def)) {
        return None
    }
    let file =
        match (def.file(db)) {
            case Source(file) => file
            case _ => return None
        }
    let top = (parentOf(db, def) ?? def).item(db)
    let call =
        (
            serverCalls(db, file).iterator().filter { one => one.read && one.top == top }.next() ??
                return None
        )
            .call
    let node = itemIdMap(db, file).node(def.item(db), parse(db, file).syntaxNode()) ?? return None
    let name = AnyHasName.cast(node).flatMap { it => it.name() }?.syntax.textRange ?? return None
    let items =
        expansionItemTree(db, call).items |>
            flatMap { item: Item => [item].concat(item.members) } |>
            map { item: Item => item.id } |>
            collectArray
    let item =
        (
            items |>
                filter {
                    id: ItemId =>
                    expansionOrigin(db, call, id).map { origin => origin[0] } == name
                } |>
                first
        ) ??
            return None
    DefId(db, ItemFile.Expansion(call), item)
}

/**
 * What a macro reported running a call of a file, where in the file: what its origin names in the source, else the
 * head of the call (`@` to the end of its attribute).
 */
@Derive[Equatable]
public struct MacroCallDiagnostic {
    public MacroCallDiagnostic(
        public let range: TextRange,
        public let severity: MacroSeverity,
        public let message: String
    ) {}
}

/**
 * What the macros the server ran reported running the calls of `file`, for the outputs that answered the request
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
    for (one in serverCalls(db, file) where current.contains(one.call)) {
        let output = macroOutputOf(db, one.call) ?? continue
        if (output.diagnostics.isEmpty()) {
            continue
        }
        let head =
            if (one.call.inBody(db).isSome()) {
                (bodyCallSyntaxOf(db, one.call) ?? continue).head()
            } else {
                let node = ids.node(one.call.item(db), root) ?? continue
                macroHeadOf(macroCallAt(node, one.call.index(db)) ?? continue)
            }
        let anchor = anchorOf(ids, root, one.top) ?? continue
        for (diagnostic in output.diagnostics) {
            let range =
                match (diagnostic.origin) {
                    case Some(FromSource(range)) where anchor + range.end <= size =>
                        TextRange(anchor + range.start, anchor + range.end)
                    case _ => head
                }
            let message =
                if (diagnostic.hint.isEmpty()) {
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
    let names = call.nameRefs() |> map { name => name.syntax.textRange.end } |> collectArray
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
    private let served = HashMap<MacroCallKey, ServerCall>()

    MacroInputComposer(
        calls: Array<ServerCall>,
        private let db: AnalysisDatabase,
        private let file: SourceFile
    ) {
        root = parse(db, file).syntaxNode()
        ids = itemIdMap(db, file)
        tree = itemTree(db, file)
        source = file.text(db).toString()
        for (one in calls) {
            served[macroCallKeyOf(db, one.call)] = one
        }
    }

    /**
     * The request for `call`; `None` if a call nested in its input has no expansion, or its item is not there. The
     * input of a call on a parameter (D119) is the parameter, as cjc gives it.
     */
    func request(call: ServerCall): ?MacroRequest {
        if (call.call.inBody(db).isSome()) {
            return requestInItem(call)
        }
        let item = call.call.item(db)
        let index = call.call.index(db)
        let anchor = anchorOf(ids, root, call.top) ?? return None
        let node = ids.node(item, root) ?? return None
        let (chain, position) = macroCallChainAt(node, index) ?? return None
        let macroCall = chain.calls[position]
        let attrs =
            macroCall
                .macroAttr()
                .map {
                    attr =>
                    let builder = MappedTextBuilder(source, anchor)
                    builder
                        .copy(innerRangeOf(attr.syntax, SyntaxKind.LBracket, SyntaxKind.RBracket))
                    builder.build()
                }
        let builder = MappedTextBuilder(source, anchor)
        let children = ArrayList<MacroChild>()
        let ready =
            if (position + 1 < chain.calls.size) {
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
     * The request for `call`, a call in an item (D117): its input what is between its parentheses, or the local
     * declaration it is on; its parents the macros on the items around it, then the calls in the item whose input it
     * is in. `None` while another call is in its input, which cjc expands first (#371), or once it is gone.
     */
    private func requestInItem(call: ServerCall): ?MacroRequest {
        let found = bodyMacroCallOf(db, call.call) ?? return None
        if (found.holdsCalls) {
            return None
        }
        let syntax = bodyCallSyntaxOf(db, call.call) ?? return None
        let anchor = anchorOf(ids, root, call.top) ?? return None
        let attrs =
            syntax
                .macroAttr()
                .map {
                    attr =>
                    let builder = MappedTextBuilder(source, anchor)
                    builder
                        .copy(innerRangeOf(attr.syntax, SyntaxKind.LBracket, SyntaxKind.RBracket))
                    builder.build()
                }
        let builder = MappedTextBuilder(source, anchor)
        match ((syntax.macroArgs(), syntax.rest())) {
            case (Some(args), _) =>
                builder.copy(innerRangeOf(args.syntax, SyntaxKind.LParen, SyntaxKind.RParen))
            case (None, Some(rest)) => builder.copy(rest.textRange)
            case _ => ()
        }
        let input = builder.build()
        let item = call.call.item(db)
        let parents = parentsOf(call.top, item, macroCountOf(item)).concat(found.around)
        let children = ArrayList<MacroChild>()
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
            case None =>
                builder.copy(TextRange(start, last.syntax.textRange.end))
                true
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
                a: (ItemId, MacroCallChain), b: (ItemId, MacroCallChain) =>
                a[1].calls[0].syntax.textRange.start.compare(b[1].calls[0].syntax.textRange.start)
            }
        )
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
