package loupe

import std.collection.*
import std.deriving.*
import calca.*
import calca.macros.*
import cjsyntax.{CjSyntaxNode, SyntaxKind}
import cjsyntax.ast.{
    AnyHasName,
    CallExpr,
    Decl,
    FinalizerDecl,
    MainDecl,
    MemberAccessExpr,
    ParenExpr,
    RefExpr,
    TrailingLambdaExpr
}
import loupe.db.{AnalysisDatabase, SourceFile}
import loupe.hir.*
import loupe.syntax.parse
import loupe.vfs.FileId

/**
 * A callable with source locations, independent of protocol positions. Without attached sources,
 * a binary callable uses the referring name's location; `definition` still identifies its overload.
 */
@Derive[Equatable]
public struct CallHierarchyEntry {
    public CallHierarchyEntry(
        public let name: String,
        public let kind: StructureKind,
        public let target: NavigationTarget,
        /**
         * Canonical binary identity, including when `target` is an attached source declaration.
         */
        public let definition!: ?DefId = None
    ) {}
}

/**
 * One caller or callee, grouping its call sites. Ranges always belong to the caller's file.
 */
public struct HierarchyCalls {
    public HierarchyCalls(
        public let item: CallHierarchyEntry,
        public let ranges: Array<TextRange>
    ) {}
}

@Derive[Equatable]
struct CallEdge {
    CallEdge(
        let caller: CallHierarchyEntry,
        let callee: CallHierarchyEntry,
        let range: TextRange
    ) {}
}

/**
 * Callable declarations named at a position; ordinary values and unresolved names have no hierarchy.
 */
public func prepareCallHierarchy(
    db: AnalysisDatabase,
    fileId: FileId,
    offset: Int64
): Array<CallHierarchyEntry> {
    let file = db.sourceFile(fileId) ?? return []
    if (inactiveReasonOf(db, file).isSome()) {
        return []
    }
    let root = parse(db, file).syntaxNode()
    let active = ActiveFilter.of(db, file)
    // Initializer navigation normally goes to its type. Here its own declaration is the root.
    for (node in root.descendants()) {
        db.unwindIfCancelled()
        if (
            let Some(entry) <- callableEntry(db, fileId, node) &&
                entry.target.focusRange.start <= offset &&
                offset <= entry.target.focusRange.end
        ) {
            if (node.ancestors().any { parent => !active.isActive(parent) }) {
                return []
            }
            return completedCallableEntries(db, file, node, entry)
        }
    }
    callableEntries(db, fileId, offset)
}

/**
 * Explicit calls to this declaration in loaded workspace source files, grouped by caller.
 * Function values are not followed through assignments; anonymous lambdas belong to their enclosing callable.
 */
public func incomingCalls(db: AnalysisDatabase, entry: CallHierarchyEntry): Array<HierarchyCalls> {
    let scope = FileScope(db)
    scope.add(db.sourceFile(entry.target.fileId))
    if (let Some(project) <- db.project()) {
        for (module in project.modules(db)) {
            for (pkg in module.packages(db)) {
                scope.addPackage(pkg)
            }
        }
    }
    // An imported alias still spells the original name in its import. Constructors can be
    // reached through type aliases or delegation, so their files cannot be filtered this way.
    let hash = wordHash(entry.name)
    let files =
        scope
            .files
            .toArray()
            .filter {
                file =>
                entry.kind == StructureKind.Constructor || fileWords(db, file).has(hash)
            }
    let edges = files.flatMap { file => callsInFile(db, file) }
    groupedCalls(edges.filter { edge => sameCallable(edge.callee, entry) }, incoming: true)
}

/**
 * Explicit calls made by this declaration, grouped by callee, excluding nested named functions.
 */
public func outgoingCalls(db: AnalysisDatabase, entry: CallHierarchyEntry): Array<HierarchyCalls> {
    let file = db.sourceFile(entry.target.fileId) ?? return []
    groupedCalls(
        callsInFile(db, file).filter { edge => sameCallable(edge.caller, entry) },
        incoming: false
    )
}

/**
 * Binary identity is independent of the referring site and of compiler/source declaration ranges.
 */
private func sameCallable(left: CallHierarchyEntry, right: CallHierarchyEntry): Bool {
    if (let Some(def) <- left.definition) {
        return right.definition == Some(def)
    }
    left == right
}

/**
 * Preserves source order and reports each site once, including calls with trailing lambdas.
 */
private func groupedCalls(edges: Array<CallEdge>, incoming!: Bool): Array<HierarchyCalls> {
    let items = ArrayList<CallHierarchyEntry>()
    let ranges = ArrayList<ArrayList<TextRange>>()
    for (edge in edges) {
        let item = if (incoming) { edge.caller } else { edge.callee }
        let index =
            (
                items.iterator() |> enumerate |>
                    filter { pair: (Int64, CallHierarchyEntry) => sameCallable(pair[1], item) } |>
                    map { pair: (Int64, CallHierarchyEntry) => pair[0] } |>
                    first
            ) ??
                items.size
        if (index == items.size) {
            items.add(item)
            ranges.add(ArrayList<TextRange>())
        }
        if (!ranges[index].contains(edge.range)) {
            ranges[index].add(edge.range)
        }
    }
    Array(items.size) { i => HierarchyCalls(items[i], ranges[i].toArray()) }
}

/**
 * Cache by file identity so expanding multiple hierarchy nodes reuses resolution of its call sites.
 */
@CalcaTracked
func callsInFile(db: AnalysisDatabase, file: SourceFile): Array<CallEdge> {
    if (inactiveReasonOf(db, file).isSome()) {
        return []
    }
    let fileId = file.fileId(db)
    let edges = ArrayList<CallEdge>()
    let active = ActiveFilter.of(db, file)
    for (node in parse(db, file).syntaxNode().descendants()) {
        db.unwindIfCancelled()
        let callee =
            CallExpr.cast(node).flatMap { call => call.callee() }?.syntax ??
                TrailingLambdaExpr.cast(node).flatMap { call => call.callee() }?.syntax ?? continue
        let range = calleeName(callee) ?? continue
        if (node.ancestors().any { parent => !active.isActive(parent) }) {
            continue
        }
        let caller =
            node.ancestors() |>
                filterMap { parent: CjSyntaxNode => callableEntry(db, fileId, parent) } |>
                first
        let owner = caller ?? continue
        for (entry in callableEntries(db, fileId, range.start)) {
            edges.add(CallEdge(owner, entry, range))
        }
    }
    edges.toArray()
}

/**
 * Resolve declarations before asking for locations: navigation omits binaries without sources.
 * Unlike navigation, a call edge names only the implementation, without its common declarations.
 */
private func callableEntries(
    db: AnalysisDatabase,
    fileId: FileId,
    offset: Int64
): Array<CallHierarchyEntry> {
    let file = db.sourceFile(fileId) ?? return []
    let token = tokenAt(parse(db, file).syntaxNode(), offset, includeInit: true) ?? return []
    let entries = ArrayList<CallHierarchyEntry>()
    for (one in callDefinitions(db, file, offset)) {
        let targets = targetsOfDefinition(db, one)
        if (!targets.isEmpty()) {
            entries.add(
                all: targets |>
                    filterMap { target: NavigationTarget => hierarchyEntry(db, target) } |>
                    collectArray
            )
            continue
        }
        let def =
            match (one) {
                case DeclDef(decl) => decl
                case _ => continue
            }
        let range = token.parent.textRange
        if (
            let Some(entry) <- binaryCallableEntry(db, def, NavigationTarget(fileId, range, range))
        ) {
            entries.add(entry)
        }
    }
    entries.toArray()
}

/**
 * A binary without attached source can still be revealed at its reference and searched by identity.
 */
private func binaryCallableEntry(
    db: AnalysisDatabase,
    def: DefId,
    reference: NavigationTarget
): ?CallHierarchyEntry {
    if (let Binary(_, _) <- def.file(db)) {
        let item = itemOf(db, def) ?? return None
        let (kind, name) =
            match (item.kind) {
                case Func =>
                    let kind =
                        if (parentOf(db, def).isSome()) {
                            StructureKind.Method
                        } else {
                            StructureKind.Function
                        }
                    (kind, item.names.get(0) ?? return None)
                case Init | PrimaryInit => (StructureKind.Constructor, "init")
                case EnumCtor => (StructureKind.EnumConstructor, item.names.get(0) ?? return None)
                case _ => return None
            }
        return CallHierarchyEntry(name, kind, reference, definition: def)
    }
    None
}

/**
 * Starting at a common declaration must reach the same body as starting at its call site.
 * A member supplied only by the common type keeps its own body and source location.
 */
private func completedCallableEntries(
    db: AnalysisDatabase,
    file: SourceFile,
    node: CjSyntaxNode,
    entry: CallHierarchyEntry
): Array<CallHierarchyEntry> {
    let def = itemAround(db, ItemFile.Source(file), node) ?? return [entry]
    if (declTarget(db, def) != Some(entry.target)) {
        return [entry]
    }
    if (let Some(specific) <- specificOf(db, def)) {
        return declTarget(db, specific)
            .flatMap { target => hierarchyEntry(db, target) }
            .map { one => [one] } ??
            [entry]
    }
    let parent = parentOf(db, def) ?? return [entry]
    let specific = specificOf(db, parent) ?? return [entry]
    let item = itemOf(db, specific) ?? return [entry]
    let entries = ArrayList<CallHierarchyEntry>()
    for (member in item.members) {
        let candidate = DefId(db, specific.file(db), member.id)
        if (commonsOf(db, candidate).contains(def)) {
            if (
                let Some(one) <- declTarget(db, candidate)
                    .flatMap { target => hierarchyEntry(db, target) }
            ) {
                entries.add(one)
            }
        }
    }
    if (entries.isEmpty()) { [entry] } else { entries.toArray() }
}

/**
 * The name actually invoked, excluding the receiver and generic arguments.
 */
func calleeName(node: CjSyntaxNode): ?TextRange {
    let reference = RefExpr.cast(node).flatMap { it => it.nameRef() }
    let member = MemberAccessExpr.cast(node).flatMap { it => it.nameRef() }
    if (let Some(name) <- reference) {
        return name.syntax.textRange
    }
    if (let Some(name) <- member) {
        return name.syntax.textRange
    }
    if (let Some(inner) <- ParenExpr.cast(node).flatMap { it => it.expr() }) {
        return calleeName(inner.syntax)
    }
    if (node.kind == SyntaxKind.ThisExpr || node.kind == SyntaxKind.SuperExpr) {
        return node.textRange
    }
    None
}

/**
 * Navigation may point at a variable or a macro origin; only callable declarations become nodes.
 */
private func hierarchyEntry(db: AnalysisDatabase, target: NavigationTarget): ?CallHierarchyEntry {
    if (target.expansion.isSome()) {
        return None
    }
    let file = db.sourceFile(target.fileId) ?? return None
    let token =
        tokenAt(parse(db, file).syntaxNode(), target.focusRange.start, includeInit: true) ??
            return None
    // Compiler ranges can omit annotations that the callable syntax node includes.
    for (node in token.parent.ancestors()) {
        if (
            let Some(entry) <- callableEntry(db, target.fileId, node) &&
                entry.target.focusRange == target.focusRange
        ) {
            return Some(entry)
        }
    }
    None
}

/**
 * The source declaration, with a keyword focus for callables without an identifier.
 */
private func callableEntry(
    db: AnalysisDatabase,
    fileId: FileId,
    node: CjSyntaxNode
): ?CallHierarchyEntry {
    let decl = Decl.cast(node) ?? return None
    let inType =
        node
            .parent
            .map {
                parent =>
                parent.kind == SyntaxKind.DeclBody || parent.kind == SyntaxKind.EnumBody
            } ??
            false
    let kind = declarationKind(decl, inType) ?? return None
    let fallback =
        match (kind) {
            case Function | Method => ""
            case Constructor => "init"
            case EnumConstructor => ""
            case Main => "main"
            case Finalizer => "~init"
            case _ => return None
        }
    let name = AnyHasName.cast(node).flatMap { it => it.name() }.map { it => it.text() } ?? fallback
    if (name.isEmpty()) {
        return None
    }
    let focus =
        MainDecl.cast(node).flatMap { it => it.mainToken() }?.textRange ??
            FinalizerDecl.cast(node).flatMap { it => it.initToken() }?.textRange ??
                declarationFocus(node)
    let target = NavigationTarget(fileId, node.textRange, focus)
    let definition =
        (db.sourceFile(fileId).flatMap { file => itemAround(db, ItemFile.Source(file), node) })
            // A local function belongs to its own syntax, not its enclosing binary declaration.
            .filter { def => declTarget(db, def) == Some(target) }
            .map { def => canonicalDef(db, def) }
            .filter {
                def =>
                match (def.file(db)) {
                    case Binary(_, _) => true
                    case _ => false
                }
            }
    CallHierarchyEntry(name, kind, target, definition: definition)
}

/**
 * Shared call-site resolution for hierarchy and audit. Preserve declaration identities before
 * navigation discards targets without source, including the selected initializer overload.
 */
func callDefinitions(db: AnalysisDatabase, file: SourceFile, offset: Int64): Array<Definition> {
    let token = tokenAt(parse(db, file).syntaxNode(), offset, includeInit: true) ?? return []
    let owner = itemAround(db, ItemFile.Source(file), token.parent)
    if (let Some(ctor) <- constructorDefinition(db, owner, token)) {
        return [Definition.DeclDef(ctor)]
    }
    classifyName(db, file, owner, token) ?? []
}
