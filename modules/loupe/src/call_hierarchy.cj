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
import loupe.hir.ActiveFilter
import loupe.syntax.parse
import loupe.vfs.FileId

/**
 * A callable declaration with source locations, independent of protocol positions.
 */
@Derive[Equatable]
public struct CallHierarchyEntry {
    public CallHierarchyEntry(
        public let name: String,
        public let kind: StructureKind,
        public let target: NavigationTarget
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
    let root = parse(db, file).syntaxNode()
    let active = ActiveFilter.of(db, file)
    // Initializer navigation normally goes to its type. Here its own declaration is the root.
    for (node in root.descendants()) {
        db.unwindIfCancelled()
        if (
            let Some(entry) <- callableEntry(fileId, node) &&
                entry.target.focusRange.start <= offset &&
                offset <= entry.target.focusRange.end
        ) {
            if (node.ancestors().any { parent => !active.isActive(parent) }) {
                return []
            }
            return [entry]
        }
    }
    definitionAt(db, fileId, offset) |>
        filterMap { target: NavigationTarget => hierarchyEntry(db, target) } |>
        collectArray
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
    groupedCalls(edges.filter { edge => edge.callee == entry }, incoming: true)
}

/**
 * Explicit calls made by this declaration, grouped by callee, excluding nested named functions.
 */
public func outgoingCalls(db: AnalysisDatabase, entry: CallHierarchyEntry): Array<HierarchyCalls> {
    let file = db.sourceFile(entry.target.fileId) ?? return []
    groupedCalls(callsInFile(db, file).filter { edge => edge.caller == entry }, incoming: false)
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
                    filter { pair: (Int64, CallHierarchyEntry) => pair[1] == item } |>
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
                filterMap { parent: CjSyntaxNode => callableEntry(fileId, parent) } |>
                first
        let owner = caller ?? continue
        for (target in definitionAt(db, fileId, range.start)) {
            if (let Some(entry) <- hierarchyEntry(db, target)) {
                edges.add(CallEdge(owner, entry, range))
            }
        }
    }
    edges.toArray()
}

/**
 * The name actually invoked, excluding the receiver and generic arguments.
 */
private func calleeName(node: CjSyntaxNode): ?TextRange {
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
    for (node in token.parent.ancestors()) {
        if (node.textRange == target.fullRange) {
            return callableEntry(target.fileId, node)
        }
    }
    None
}

/**
 * The source declaration, with a keyword focus for callables without an identifier.
 */
private func callableEntry(fileId: FileId, node: CjSyntaxNode): ?CallHierarchyEntry {
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
    CallHierarchyEntry(name, kind, NavigationTarget(fileId, node.textRange, focus))
}
