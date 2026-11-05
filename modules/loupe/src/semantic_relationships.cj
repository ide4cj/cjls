package loupe

import std.collection.{ArrayList, HashSet, collectArray, filterMap}
import cjsyntax.{CjSyntaxNode, CjSyntaxToken, SyntaxKind}
import cjsyntax.ast.Param
import ginkgo.SyntaxNodePtr
import loupe.db.{AnalysisDatabase, SourceFile}
import loupe.hir.{
    ActiveFilter,
    DefId,
    ExprId,
    ExtendedType,
    Item,
    ItemFile,
    ItemKind,
    LocalId,
    PackageRef,
    TypeTarget,
    activeItemTree,
    bodyWithSourceMap,
    canonicalDef,
    extendedTypeOf,
    extendsOf,
    genericsOf,
    importersOf,
    inactiveReasonOf,
    overriddenMembers,
    overridingMembers,
    packageOfFile,
    packageSubtypes,
    parentOf,
    resolutionPackage,
    scopeFileOf,
    sourceDefOf,
    supertypes
}
import loupe.syntax.parse

/**
 * A callable owner, or a contextual file when the occurrence is outside a callable.
 * Local named functions and lambdas retain their own body identities.
 */
public enum SemanticOwner {
    | ObjectOwner(SemanticObject)
    | FileOwner(ItemFile)
}

/**
 * One semantic usage. Contextual locations are intentionally not deduplicated by physical path.
 */
public struct SemanticUsage {
    SemanticUsage(
        public let target: SemanticObject,
        public let location: SemanticLocation,
        public let owner: SemanticOwner,
        public let access: ?ReferenceAccess,
        public let isDeclaration: Bool
    ) {}
}

/**
 * Written-source usages and explicit coverage omissions. Gaps are stable reason strings;
 * macro-origin-usages means generated occurrences are outside the written reference model.
 */
public struct SemanticUsages {
    SemanticUsages(public let entries: Array<SemanticUsage>, public let gaps: Array<String>) {}
}

/**
 * A possible immediate call; candidate resolution and conservative dispatch survive composition.
 */
public struct SemanticCallEdge {
    SemanticCallEdge(
        public let caller: SemanticObject,
        public let callee: SemanticObject,
        public let site: SemanticLocation,
        public let resolution: String,
        public let isConservative: Bool
    ) {}
}

/**
 * The original partial-call omission, retaining the caller's contextual source when available.
 */
public struct SemanticCallGap {
    SemanticCallGap(public let reason: String, public let site: ?SemanticLocation) {}
}

/**
 * Immediate possible calls and explicit omissions; absence never proves runtime purity (A39).
 */
public struct SemanticCalls {
    SemanticCalls(
        public let edges: Array<SemanticCallEdge>,
        public let gaps: Array<SemanticCallGap>
    ) {}
}

/**
 * A direct inheritance edge. Owner is the declaration writing the supertype; an extend also
 * records its provenance independently of the type it extends.
 */
public struct SemanticHierarchyEdge {
    SemanticHierarchyEdge(
        public let subtype: SemanticObject,
        public let supertype: SemanticObject,
        public let owner: SemanticObject,
        public let extension: ?SemanticObject
    ) {}
}

/**
 * An immediate overridden/implemented member, with the implementing member's declaration owner.
 */
public struct SemanticImplementationEdge {
    SemanticImplementationEdge(
        public let implementation: SemanticObject,
        public let declaration: SemanticObject,
        public let owner: SemanticObject,
        public let extension: ?SemanticObject
    ) {}
}

extend SemanticObject {
    /**
     * On-demand identity search, reusing reference scopes, aliases and word filtering. None means
     * the object is not a searchable named identity (packages included). Empty entries apply within the returned gaps.
     * Inactive code is excluded. Macro arguments retain written identity; generated usages are
     * currently unavailable, matching findReferences rather than pretending expansion completeness.
     * Explicit inPackages searches those contextual files instead of the default reference scope.
     * It also reads scope aliases, allowing reverse import traversal through renamed re-exports.
     * Packages must originate from this same SemanticAnalysis; binaries have no written usages.
     */
    public func usages(inPackages!: ?Array<SemanticPackage> = None): ?SemanticUsages {
        let db = analysis.db
        db.unwindIfCancelled()
        let definition = relationshipDefinition() ?? return None
        let names = usageNames(definition)
        if (names.isEmpty()) {
            return SemanticUsages([], ["unsupported-name"])
        }
        let from = relationshipFile(definition)
        let files =
            if (let Some(packages) <- inPackages) {
                let files = ArrayList<SourceFile>()
                for (pkg in packages) {
                    if (!refEq(pkg.analysis, analysis)) {
                        throw IllegalArgumentException(
                            "usage scope must belong to the same SemanticAnalysis"
                        )
                    }
                    for (file in pkg.files()) {
                        if (let Source(source) <- file.identity && !files.contains(source)) {
                            files.add(source)
                        }
                    }
                }
                files.toArray()
            } else if (let Some(file) <- from) {
                searchScope(db, [definition], file)
            } else {
                let scope = relationshipScope(db)
                scope.files.toArray()
            }
        let hashes = names.map { name => wordHash(name) }
        let found = ArrayList<SemanticUsage>()
        for (file in files) {
            if (inactiveReasonOf(db, file).isSome()) {
                continue
            }
            if (inPackages.isNone() && !hashes.any { hash => fileWords(db, file).has(hash) }) {
                continue
            }
            let root = parse(db, file).syntaxNode()
            let active = ActiveFilter.of(db, file)
            let scopeNames: Array<String> =
                if (inPackages.isSome()) {
                    (SemanticFile(analysis, ItemFile.Source(file)).visibleNames() ?? [])
                        .filter { binding => binding.target.identity == identity }
                        .map { binding => binding.name }
                } else {
                    []
                }
            let candidates = names.concat(scopeNames)
            let aliases = aliasesIn(db, file, root, candidates, [definition])
            for (token in namesMeaning(db, file, root, candidates.concat(aliases), [definition])) {
                if (token.parent.ancestors().any { node => !active.isActive(node) }) {
                    continue
                }
                let itemFile = ItemFile.Source(file)
                found.add(
                    SemanticUsage(
                        this,
                        analysis.location(itemFile, token.textRange, token.textRange),
                        semanticUsageOwner(analysis, itemFile, token),
                        accessOf(token),
                        declares(token)
                    )
                )
            }
        }
        let gaps = ArrayList<String>(["macro-origin-usages"])
        if (
            let Some(packages) <- inPackages &&
                packages
                    .iterator()
                    .any {
                        pkg =>
                        match (pkg.identity) {
                            case Binary(_) => true;
                            case _ => false
                        }
                    }
        ) {
            gaps.add("binary-source-usages")
        }
        SemanticUsages(found.toArray(), gaps.toArray())
    }

    func relationshipDefinition(): ?Definition {
        match (identity) {
            case NamedIdentity(PackageDef(_)) => None
            case NamedIdentity(MemberParamDef(owner, id)) => Definition.LocalDef(owner, id)
            case NamedIdentity(definition) => definition
            case LocalIdentity(owner, id) => Definition.LocalDef(owner, id)
            case _ => None
        }
    }

    private func relationshipFile(definition: Definition): ?SourceFile {
        let db = analysis.db
        match (definition) {
            case DeclDef(id) => scopeFileOf(db, id.file(db))
            case LocalDef(id, _) => scopeFileOf(db, id.file(db))
            case MemberParamDef(id, _) => scopeFileOf(db, id.file(db))
            case TypeParamDef(GenericOf(id, _)) => scopeFileOf(db, id.file(db))
            case TypeParamDef(LocalGenericOf(id, _, _)) => scopeFileOf(db, id.file(db))
            case _ => None
        }
    }

    private func usageNames(definition: Definition): Array<String> {
        let db = analysis.db
        match (definition) {
            case DeclDef(id) => itemIn(db, id)?.names ?? []
            case LocalDef(owner, id) =>
                bodyWithSourceMap(db, owner)
                    .body
                    .locals
                    .get(id.index)
                    .map { local => [local.name] } ??
                    []
            case TypeParamDef(GenericOf(owner, index)) =>
                genericsOf(db, owner).get(index).map { name => [name] } ?? []
            case TypeParamDef(LocalGenericOf(owner, function, index)) =>
                bodyWithSourceMap(db, owner)
                    .body
                    .funcs
                    .get(function)
                    .flatMap { local => local.generics.get(index) }
                    .map { name => [name] } ??
                    []
            case _ => []
        }
    }

    /**
     * Reuses directCalls and every A39 gap. Nested named functions/lambdas are scanned only when
     * explicitly selected as the owner; declaring them contributes no calls to the outer body.
     * Attached binary bodies are used when checked source is available; otherwise unavailable-body.
     */
    public func outgoingCalls(): SemanticCalls {
        let db = analysis.db
        db.unwindIfCancelled()
        let (owner, node) = relationshipBody()
        let result =
            if (let Some(def) <- owner) {
                if (let Some(body) <- node && let Some(file) <- scopeFileOf(db, def.file(db))) {
                    let scan = DirectCallScan(db, def, file, ActiveFilter.of(db, file))
                    if (!parse(db, file).errors.isEmpty()) {
                        scan.gap("malformed-source", body)
                    }
                    for (child in body.children()) {
                        if (
                            child.kind == SyntaxKind.Block ||
                                (
                                    body.kind == SyntaxKind.LambdaExpr &&
                                        child.kind != SyntaxKind.LambdaParamList
                                )
                        ) {
                            scan.visit(child)
                        }
                        if (
                            child.kind == SyntaxKind.ParamList &&
                                child
                                    .children()
                                    .any {
                                        param =>
                                        Param.cast(param).flatMap { one => one.expr() }.isSome()
                                    }
                        ) {
                            scan.gap("default-arguments", child)
                        }
                    }
                    DirectCalls(scan.edges.toArray(), scan.gaps.toArray())
                } else {
                    directCalls(db, def)
                }
            } else {
                DirectCalls([], [CallGap("unavailable-body", None)])
            }
        let file = owner.map { def => def.file(db) }
        SemanticCalls(
            result
                .edges
                .map {
                    edge =>
                    SemanticCallEdge(
                        this,
                        analysis.object(
                            NamedIdentity(DeclDef(callDeclaration(db, edge.target).definition))
                        ),
                        analysis.location(
                            file.getOrThrow(),
                            edge.site.fullRange,
                            edge.site.focusRange
                        ),
                        edge.resolution,
                        edge.isConservative
                    )
                },
            result
                .gaps
                .map {
                    gap =>
                    SemanticCallGap(
                        gap.reason,
                        gap
                            .site
                            .flatMap {
                                site =>
                                file
                                    .map {
                                        one =>
                                        analysis.location(one, site.fullRange, site.focusRange)
                                    }
                            }
                    )
                }
        )
    }

    private func relationshipBody(): (?DefId, ?CjSyntaxNode) {
        let db = analysis.db
        match (identity) {
            case NamedIdentity(DeclDef(id)) => (Some(sourceDefOf(db, id) ?? id), None)
            case LocalIdentity(owner, local) =>
                let lowered = bodyWithSourceMap(db, owner)
                if (!lowered.body.funcs.any { one => one.local == local && one.body.isSome() }) {
                    return (None, None)
                }
                let origin =
                    lowered.sourceMap.locals.get(local.index).flatMap { one => one.written } ??
                        return (None, None)
                if (origin.inFile(owner.file(db)) != owner.file(db)) {
                    return (None, None)
                }
                let node =
                    origin.node(db, owner.file(db)).flatMap { name => name.parent } ??
                        return (None, None)
                (Some(owner), Some(node))
            case ExpressionIdentity(owner, id) =>
                let origin =
                    bodyWithSourceMap(db, owner)
                        .sourceMap
                        .exprs
                        .get(id.index)
                        .flatMap { one => one.written } ??
                        return (None, None)
                if (origin.inFile(owner.file(db)) != owner.file(db)) {
                    return (None, None)
                }
                let node = origin.node(db, owner.file(db)) ?? return (None, None)
                if (node.kind == SyntaxKind.LambdaExpr) {
                    (Some(owner), Some(node))
                } else {
                    (None, None)
                }
            case _ => (None, None)
        }
    }

    /**
     * Incoming evidence over loaded workspace source contexts, using directCalls' partial model.
     * Repeated sites and candidate targets survive. Unavailable callers and callback/value flow
     * are not enumerated; inspect each caller's outgoingCalls gaps before making reachability claims.
     */
    public func incomingCalls(): Array<SemanticCallEdge> {
        let db = analysis.db
        db.unwindIfCancelled()
        let target =
            match (identity) {
                case NamedIdentity(DeclDef(id)) => callDeclaration(db, id).definition
                case _ => return []
            }
        let edges = ArrayList<SemanticCallEdge>()
        let name = callDeclaration(db, target).name
        let isConstructor =
            target.item(db).kind == ItemKind.Init || target.item(db).kind == ItemKind.PrimaryInit
        let canFilterName =
            !name.isEmpty() && name.toArray().all { byte => byte >= 0x80 || isAsciiWordByte(byte) }
        let scope = relationshipScope(db)
        scope.add(relationshipFile(relationshipDefinition().getOrThrow()))
        for (file in scope.files) {
            db.unwindIfCancelled()
            if (!isConstructor && canFilterName && !fileWords(db, file).has(wordHash(name))) {
                continue
            }
            if (inactiveReasonOf(db, file).isSome()) {
                continue
            }
            for (owner in relationshipCallables(analysis, file)) {
                edges.add(
                    all: owner
                        .outgoingCalls()
                        .edges
                        .filter { edge => edge.callee.identity == NamedIdentity(DeclDef(target)) }
                )
            }
        }
        edges.toArray()
    }

    /**
     * Immediate supertypes, including extensions visible from the declaration context.
     * Every extension keeps its own owner; never returns the transitive closure.
     */
    public func directSupertypes(): Array<SemanticHierarchyEdge> {
        let db = analysis.db
        db.unwindIfCancelled()
        let id =
            match (identity) {
                case NamedIdentity(DeclDef(id)) => id;
                case _ => return []
            }
        let extension: ?SemanticObject =
            if (id.item(db).kind == ItemKind.Extend) { Some(this) } else { None }
        let subtype =
            if (id.item(db).kind == ItemKind.Extend &&
                let Some(DeclType(extended)) <- extendedTypeOf(db, id)) {
                analysis.object(NamedIdentity(DeclDef(extended)))
            } else {
                this
            }
        let own =
            supertypes(db, id) |>
                filterMap {
                    supertype: ExtendedType =>
                    match (supertype) {
                        case DeclType(sup) =>
                            Some(
                                SemanticHierarchyEdge(
                                    subtype,
                                    analysis.object(NamedIdentity(DeclDef(sup))),
                                    this,
                                    extension
                                )
                            )
                        case _ => None<SemanticHierarchyEdge>
                    }
                } |>
                collectArray
        if (id.item(db).kind == ItemKind.Extend) {
            return own
        }
        own.concat(
            extendsOf(db, ExtendedType.DeclType(id), scopeFileOf(db, id.file(db)))
                .flatMap { ext => analysis.object(NamedIdentity(DeclDef(ext))).directSupertypes() }
        )
    }

    /**
     * Immediate reverse edges from the existing package subtype cache. Distinct extend owners
     * remain distinct even when they implement the same type-to-interface relationship.
     */
    public func directSubtypes(): Array<SemanticHierarchyEdge> {
        let db = analysis.db
        db.unwindIfCancelled()
        let id =
            match (identity) {
                case NamedIdentity(DeclDef(id)) => id;
                case _ => return []
            }
        let packages = relationshipPackage(db, id).map { pkg => importersOf(db, pkg) } ?? []
        let edges = ArrayList<SemanticHierarchyEdge>()
        for (pkg in packages) {
            for (sub in packageSubtypes(db, pkg).get(id) ?? []) {
                edges.add(
                    all: analysis
                        .object(NamedIdentity(DeclDef(sub)))
                        .directSupertypes()
                        .filter { edge => edge.supertype.identity == identity }
                )
            }
        }
        edges.toArray()
    }

    /**
     * Immediate member relationships: a candidate overridden through a nearer matching member
     * is excluded. Shared ancestors in a diamond appear once by declaration identity.
     */
    public func directImplementations(): Array<SemanticImplementationEdge> {
        let db = analysis.db
        db.unwindIfCancelled()
        let id =
            match (identity) {
                case NamedIdentity(DeclDef(id)) => id;
                case _ => return []
            }
        let all = overriddenMembers(db, id)
        let nearest =
            all
                .filter {
                    candidate =>
                    !all
                        .any {
                            other =>
                            other != candidate && overriddenMembers(db, other).contains(candidate)
                        }
                }
        let parent = parentOf(db, id) ?? return []
        let owner = analysis.object(NamedIdentity(DeclDef(parent)))
        let extension: ?SemanticObject =
            if (parent.item(db).kind == ItemKind.Extend) { Some(owner) } else { None }
        nearest
            .flatMap {
                candidate =>
                let target = analysis.object(NamedIdentity(DeclDef(candidate)))
                if (extension.isSome()) {
                    return [SemanticImplementationEdge(this, target, owner, extension)]
                }
                let declaring =
                    parentOf(db, candidate) ??
                        return [SemanticImplementationEdge(this, target, owner, None)]
                let from = scopeFileOf(db, id.file(db))
                let provenance =
                    extendsOf(db, ExtendedType.DeclType(parent), from)
                        .filter { ext => relationshipInherits(db, ext, declaring) }
                if (provenance.isEmpty() || relationshipInherits(db, parent, declaring)) {
                    return [SemanticImplementationEdge(this, target, owner, None)]
                }
                provenance
                    .map {
                        ext =>
                        SemanticImplementationEdge(
                            this,
                            target,
                            owner,
                            Some(analysis.object(NamedIdentity(DeclDef(ext))))
                        )
                    }
            }
    }
    /**
     * Immediate reverse implementation edges. The candidate search is transitive, but each
     * returned edge passes the same nearest-member rule as directImplementations.
     */
    public func directImplementers(): Array<SemanticImplementationEdge> {
        let db = analysis.db
        db.unwindIfCancelled()
        let id =
            match (identity) {
                case NamedIdentity(DeclDef(id)) => id;
                case _ => return []
            }
        overridingMembers(db, id)
            .flatMap {
                candidate =>
                analysis
                    .object(NamedIdentity(DeclDef(candidate)))
                    .directImplementations()
                    .filter { edge => edge.declaration.identity == identity }
            }
    }
}

func relationshipScope(db: AnalysisDatabase): FileScope {
    let scope = FileScope(db)
    if (let Some(project) <- db.project()) {
        for (module in project.modules(db)) {
            for (pkg in module.packages(db)) {
                scope.addPackage(pkg)
            }
        }
    }
    scope
}

func relationshipCallables(analysis: SemanticAnalysis, file: SourceFile): Array<SemanticObject> {
    let db = analysis.db
    let found = ArrayList<SemanticObject>()
    let itemFile = ItemFile.Source(file)
    let pending = ArrayList<Item>(activeItemTree(db, file).items)
    var index = 0
    while (index < pending.size) {
        db.unwindIfCancelled()
        let item = pending[index]
        index++
        pending.add(all: item.members)
        if (!relationshipCallableKind(item.kind)) {
            continue
        }
        let def = DefId(db, itemFile, item.id)
        found.add(analysis.object(NamedIdentity(DeclDef(def))))
        let lowered = bodyWithSourceMap(db, def)
        for (local in lowered.body.funcs) {
            found.add(analysis.object(LocalIdentity(def, local.local)))
        }
        for (i in 0..lowered.body.exprs.size) {
            let source =
                lowered.sourceMap.exprs.get(i).flatMap { origin => origin.written } ?? continue
            let node = source.node(db, itemFile) ?? continue
            if (node.kind == SyntaxKind.LambdaExpr) {
                found.add(analysis.object(ExpressionIdentity(def, ExprId(i))))
            }
        }
    }
    found.toArray()
}

func semanticUsageOwner(
    analysis: SemanticAnalysis,
    file: ItemFile,
    token: CjSyntaxToken
): SemanticOwner {
    let db = analysis.db
    let owner = itemAround(db, file, token.parent) ?? return FileOwner(file)
    let lowered = bodyWithSourceMap(db, owner)
    for (node in token.parent.ancestors()) {
        if (
            node.kind == SyntaxKind.LambdaExpr &&
                let Some(expr) <- lowered.sourceMap.exprAt(SyntaxNodePtr(node))
        ) {
            return ObjectOwner(analysis.object(ExpressionIdentity(owner, expr)))
        }
        if (node.kind == SyntaxKind.FuncDecl) {
            for (local in lowered.body.funcs) {
                let source =
                    lowered.sourceMap.locals.get(local.local.index).flatMap { one => one.written }
                if (
                    source
                        .flatMap { origin => origin.node(db, file) }
                        .flatMap { name => name.parent } ==
                        Some(node)
                ) {
                    return ObjectOwner(analysis.object(LocalIdentity(owner, local.local)))
                }
            }
        }
    }
    let kind = owner.item(db).kind
    if (relationshipCallableKind(kind)) {
        ObjectOwner(analysis.object(NamedIdentity(DeclDef(canonicalDef(db, owner)))))
    } else {
        FileOwner(file)
    }
}

func relationshipPackage(db: AnalysisDatabase, id: DefId): ?PackageRef {
    match (id.file(db)) {
        case Binary(pkg, _) => PackageRef.Binary(pkg)
        case CompilerBuiltIns(pkg) => PackageRef.Source(pkg)
        case file =>
            scopeFileOf(db, file)
                .flatMap { source => packageOfFile(db, source) }
                .map { pkg => resolutionPackage(db, pkg) }
    }
}

func relationshipInherits(db: AnalysisDatabase, start: DefId, target: DefId): Bool {
    let pending = ArrayList<DefId>([start])
    let seen = HashSet<DefId>()
    var index = 0
    while (index < pending.size) {
        db.unwindIfCancelled()
        let id = pending[index]
        index++
        if (!seen.add(id)) {
            continue
        }
        for (sup in supertypes(db, id)) {
            if (let DeclType(parent) <- sup) {
                if (parent == target) {
                    return true
                }
                pending.add(parent)
            }
        }
    }
    false
}

func relationshipCallableKind(kind: ItemKind): Bool {
    match (kind) {
        case Func | Main | Finalizer | Init | PrimaryInit | Prop => true
        case _ => false
    }
}
