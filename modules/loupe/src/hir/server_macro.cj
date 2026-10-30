package loupe.hir

import std.collection.{
    ArrayList,
    HashMap,
    HashSet,
    collectArray,
    filter,
    filterMap,
    first,
    flatMap,
    map
}
import std.deriving.*
import calca.*
import calca.macros.*
import cjsyntax.{CjSyntaxNode, message}
import cjsyntax.ast.{AnyHasName, MacroExpandDecl}
import ginkgo.TextRange
import loupe.db.{
    AnalysisDatabase,
    BinaryPackageFile,
    MacroCallKey,
    MacroItem,
    MacroOutput,
    MacroOutputs,
    MacroSeverity,
    MappedText,
    Package,
    SourceFile,
    SpanOrigin
}
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
 * expanded and read by nothing of its own (#176). A call in an item is read in its body's current expansion (D144).
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
            if (let Some(calls) <- inItems.get(item)) {
                for (one in calls) {
                    let owner = pkg ?? break
                    let path = one.name.split(".")
                    let definition =
                        serverMacroOf(db, resolveMacroPath(db, owner, file, path)[path.size - 1]) ??
                            continue
                    // std's expression calls keep their fallback until #375 sends them to the server
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
        }
    for (item in itemTree(db, file).items) {
        let own: Array<ServerCall> =
            if (hasMacroCalls(item)) { serverCallsOn(db, file, item, item.id, true) } else { [] }
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
        if (output.diagnostics.isEmpty() && one.call.inBody(db).isNone()) {
            continue
        }
        let head =
            if (one.call.inBody(db).isSome()) {
                (bodyCallSyntaxOf(db, one.call) ?? continue).head()
            } else {
                let node = ids.node(one.call.item(db), root) ?? continue
                macroHeadOf(macroCallAt(node, one.call.index(db)) ?? continue)
            }
        if (
            one.call.inBody(db).isSome() && output.expansion.isSome() &&
                !output
                    .diagnostics
                    .any { diagnostic => diagnostic.severity == MacroSeverity.MacroError }
        ) {
            for (error in expansionParse(db, one.call).errors) {
                found
                    .add(
                        MacroCallDiagnostic(
                            head,
                            MacroSeverity.MacroError,
                            "macro expansion: ${message(error.error)}"
                        )
                    )
            }
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
