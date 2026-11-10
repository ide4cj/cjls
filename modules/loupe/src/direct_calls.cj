package loupe

import std.collection.ArrayList
import calca.*
import calca.macros.*
import cjsyntax.{CjSyntaxNode, SyntaxKind}
import cjsyntax.ast.{CallExpr, Param, TrailingLambdaExpr}
import ginkgo.SyntaxNodePtr
import py_interop.*
import py_interop.internal_macros.DerivePython
import loupe.db.{AnalysisDatabase, SourceFile}
import loupe.hir.{
    ActiveFilter,
    BodySource,
    DefId,
    Item,
    ItemFile,
    ItemKind,
    Modifier,
    Resolution,
    activeItemTree,
    bodyWithSourceMap,
    canonicalDef,
    expandedDeclOf,
    inactiveReasonOf,
    inferBody,
    itemOf,
    macroPathOf,
    macrosOf,
    packageOfFile,
    parentOf
}
import loupe.syntax.parse
import loupe.vfs.FileId

/**
 * A possible immediate call at a UTF-8 source site. Targets belong to the producing database/revision.
 * `resolution` is `resolved-declaration` for an explicit call, `inferred-operator` for a selected
 * operator overload, or `candidate` for an ambiguous or virtual target. A candidate has
 * `isConservative` set; any chain containing it must retain that qualification.
 */
@DerivePython
@PyDoc["A possible immediate call at a UTF-8 source site. Targets belong to the producing database/revision. `resolution` is `resolved-declaration` for an explicit call, `inferred-operator` for a selected operator overload, or `candidate` for an ambiguous or virtual target. A candidate has `isConservative` set; any chain containing it must retain that qualification."]
public struct DirectCall <: Equatable<DirectCall> {
    public DirectCall(
        public let target: DefId,
        public let site: NavigationTarget,
        public let resolution: String,
        public let isConservative!: Bool
    ) {}
    public operator func ==(other: DirectCall): Bool {
        target == other.target && site == other.site && isConservative == other.isConservative &&
            resolution == other.resolution
    }
    public operator func !=(other: DirectCall): Bool {
        !(this == other)
    }
}

/**
 * Coverage information, not a source diagnostic. A missing body may have no source site.
 * Stable `reason` strings identify the omitted behavior:
 * - `unavailable-body`: binary/expansion body, absent block or removed declaration.
 * - `unresolved-call`: no declaration-backed callable target resolved.
 * - `functional-value`: invocation of a local function, lambda, parameter, variable or expression.
 * - `functional-value-or-constructor`: a value/type without a selected callable declaration.
 * - `callback-flow`: a call has arguments; callback transfer/invocation is not modeled.
 *   This deliberately includes arguments that are not callbacks.
 * - `virtual-dispatch`: possible runtime implementations of a static target are not enumerated.
 * - `implicit-initialization`: field, base or other implicit construction effects.
 * - `implicit-operator`: operator effects are incomplete, even with a selected overload edge.
 * - `property-or-initialization`: getter/setter or declaration-backed value initialization.
 * - `unresolved-value`: value resolution is unavailable.
 * - `default-arguments`: default values are not unconditional body calls.
 * - `implicit-conversion`: interpolation may invoke user conversion code.
 * - `malformed-source`: parse recovery may have omitted executable code.
 * - `iteration-protocol`, `resource-protocol`, `spawn-boundary`: implicit protocol/execution effects.
 * - `declaration-macro`, `body-macro`: macro behavior outside the transparent CalcaTracked policy.
 */
@DerivePython
@PyDoc["Coverage information, not a source diagnostic. A missing body may have no source site. Stable `reason` strings identify the omitted behavior: - `unavailable-body`: binary/expansion body, absent block or removed declaration. - `unresolved-call`: no declaration-backed callable target resolved. - `functional-value`: invocation of a local function, lambda, parameter, variable or expression. - `functional-value-or-constructor`: a value/type without a selected callable declaration. - `callback-flow`: a call has arguments; callback transfer/invocation is not modeled. This deliberately includes arguments that are not callbacks. - `virtual-dispatch`: possible runtime implementations of a static target are not enumerated. - `implicit-initialization`: field, base or other implicit construction effects. - `implicit-operator`: operator effects are incomplete, even with a selected overload edge. - `property-or-initialization`: getter/setter or declaration-backed value initialization. - `unresolved-value`: value resolution is unavailable. - `default-arguments`: default values are not unconditional body calls. - `implicit-conversion`: interpolation may invoke user conversion code. - `malformed-source`: parse recovery may have omitted executable code. - `iteration-protocol`, `resource-protocol`, `spawn-boundary`: implicit protocol/execution effects. - `declaration-macro`, `body-macro`: macro behavior outside the transparent CalcaTracked policy."]
public struct CallGap <: Equatable<CallGap> {
    public CallGap(public let reason: String, public let site: ?NavigationTarget) {}
    public operator func ==(other: CallGap): Bool {
        reason == other.reason && site == other.site
    }
    public operator func !=(other: CallGap): Bool {
        !(this == other)
    }
}

/**
 * Immediate edges and omissions in a partial possible-call model. Both conditional branches
 * contribute; edges do not prove execution. Empty edges with gaps leave reachability unknown.
 * Even a traversal without gaps establishes absence only within this model: compiler/runtime
 * effects such as allocation, finalization and implicit string conversion may remain unmodeled.
 * This result cannot certify general language-level purity.
 */
@DerivePython
@PyDoc["Immediate edges and omissions in a partial possible-call model. Both conditional branches contribute; edges do not prove execution. Empty edges with gaps leave reachability unknown. Even a traversal without gaps establishes absence only within this model: compiler/runtime effects such as allocation, finalization and implicit string conversion may remain unmodeled. This result cannot certify general language-level purity."]
public struct DirectCalls <: Equatable<DirectCalls> {
    public DirectCalls(public let edges: Array<DirectCall>, public let gaps: Array<CallGap>) {}
    public operator func ==(other: DirectCalls): Bool {
        edges == other.edges && gaps == other.gaps
    }
    public operator func !=(other: DirectCalls): Bool {
        !(this == other)
    }
}

/**
 * Canonical declaration metadata, with an optional navigation location. Match targets by identity
 * and ownership rather than source spelling: package ownership is independent of import aliases.
 * Declaration identities belong to their producing analysis database and revision.
 */
@DerivePython
@PyDoc["Canonical declaration metadata, with an optional navigation location. Match targets by identity and ownership rather than source spelling: package ownership is independent of import aliases. Declaration identities belong to their producing analysis database and revision."]
public struct CallDeclaration {
    public CallDeclaration(
        public let definition: DefId,
        public let packageName: String,
        public let name: String,
        public let ownerName: String,
        public let location: ?NavigationTarget
    ) {}
}

/**
 * Declaring package ownership, including binary and expansion declarations.
 */
private func auditPackage(db: AnalysisDatabase, definition: DefId): String {
    match (definition.file(db)) {
        case Binary(pkg, _) => pkg.name(db)
        case Source(file) => packageOfFile(db, file).map { pkg => pkg.name(db) } ?? ""
        case Expansion(call) => packageOfFile(db, call.file(db)).map { pkg => pkg.name(db) } ?? ""
        case _ => ""
    }
}

/**
 * Recognize the transparent macro by its resolved owner, including renamed imports.
 */
private func isTrackedMacro(db: AnalysisDatabase, resolution: Resolution): Bool {
    match (macroPathOf(db, resolution)) {
        case Some((pkg, name)) => pkg == "calca.macros" && name == "CalcaTracked"
        case None => false
    }
}

/**
 * Active original functions whose macro resolves to `calca.macros.CalcaTracked`, including renamed
 * imports. Returns no roots for a missing or inactive file.
 */
public func trackedCallRoots(db: AnalysisDatabase, fileId: FileId): Array<DefId> {
    let file = db.sourceFile(fileId) ?? return []
    if (inactiveReasonOf(db, file).isSome()) {
        return []
    }
    let result = ArrayList<DefId>()
    let pending = ArrayList<Item>(activeItemTree(db, file).items)
    var index = 0
    while (index < pending.size) {
        let item = pending[index]
        index++
        pending.add(all: item.members)
        let def = DefId(db, ItemFile.Source(file), item.id)
        if (
            item.kind == ItemKind.Func && macrosOf(db, def).any { one => isTrackedMacro(db, one) }
        ) {
            result.add(def)
        }
    }
    result.toArray()
}

/**
 * Normalize a copied CalcaTracked name back to the written callable, never its generated wrapper.
 */
private func auditDefinition(db: AnalysisDatabase, def: DefId): DefId {
    if (let Expansion(call) <- def.file(db)) {
        let file = call.file(db)
        let pending = ArrayList<Item>(activeItemTree(db, file).items)
        var index = 0
        while (index < pending.size) {
            let item = pending[index]
            index++
            pending.add(all: item.members)
            let original = DefId(db, ItemFile.Source(file), item.id)
            if (!macrosOf(db, original).any { one => isTrackedMacro(db, one) }) {
                continue
            }
            if (expandedDeclOf(db, original) == Some(def)) {
                return original
            }
        }
    }
    def
}

/**
 * Canonical identity, ownership and optional source location of a callable. Copied CalcaTracked
 * declarations map back to their original source identity.
 */
public func callDeclaration(db: AnalysisDatabase, def: DefId): CallDeclaration {
    let canonical = canonicalDef(db, auditDefinition(db, def))
    let packageName = auditPackage(db, canonical)
    CallDeclaration(
        canonical,
        packageName,
        itemOf(db, canonical).flatMap { item => item.names.get(0) } ?? "",
        parentOf(db, canonical)
            .flatMap { parent => itemOf(db, parent).flatMap { item => item.names.get(0) } } ??
            "",
        declTarget(db, canonical)
    )
}

/**
 * On-demand, intraprocedural call model of the original source body. Explicit declaration calls,
 * methods, selected overloads and initializers contribute edges. Selected operators also retain
 * an incompleteness gap. Unavailable bodies return an `unavailable-body` gap.
 *
 * CalcaTracked is transparent: generated runtime wrappers contribute no calls. Other declaration
 * macros add a gap; body macro inputs are skipped. Nested functions and lambdas are not executed
 * by their declaration; invoking their values adds a gap. Assignments, parameters and returned
 * values do not yet carry functional value flow. See CallGap for stable omission reasons.
 */
@CalcaTracked
public func directCalls(db: AnalysisDatabase, def: DefId): DirectCalls {
    let file =
        match (def.file(db)) {
            case Source(source) => source
            case _ => return DirectCalls([], [CallGap("unavailable-body", None)])
        }
    let node = itemNodeOf(db, def) ?? return DirectCalls([], [CallGap("unavailable-body", None)])
    let scan = DirectCallScan(db, def, file, ActiveFilter.of(db, file))
    let item = itemOf(db, def) ?? return DirectCalls([], [CallGap("unavailable-body", None)])
    // CalcaTracked is intentionally transparent: the audit concerns the original user body.
    if (macrosOf(db, def).any { one => !isTrackedMacro(db, one) }) {
        scan.gap("declaration-macro", node)
    }
    if (!parse(db, file).errors.isEmpty()) {
        scan.gap("malformed-source", node)
    }
    var hasBody = false
    for (child in node.children()) {
        if (child.kind == SyntaxKind.Block) {
            hasBody = true
            scan.visit(child)
        }
        if (child.kind == SyntaxKind.PropBody) {
            // A property identity groups both potential accessor bodies; reading a property
            // elsewhere still reports property-or-initialization rather than an implicit call.
            for (accessor in child.children()) {
                for (block in accessor.children() where block.kind == SyntaxKind.Block) {
                    hasBody = true
                    scan.visit(block)
                }
            }
        }
        if (child.kind == SyntaxKind.ParamList) {
            // Default arguments execute at a call site, not unconditionally in this body.
            if (
                child
                    .children()
                    .any { one => Param.cast(one).flatMap { param => param.expr() }.isSome() }
            ) {
                scan.gap("default-arguments", child)
            }
        }
    }
    if (!hasBody) {
        scan.gap("unavailable-body", node)
    }
    if (item.kind == ItemKind.Init || item.kind == ItemKind.PrimaryInit) {
        scan.gap("implicit-initialization", node)
    }
    DirectCalls(scan.edges.toArray(), scan.gaps.toArray())
}

class DirectCallScan {
    DirectCallScan(
        let db: AnalysisDatabase,
        let def: DefId,
        let file: SourceFile,
        let active: ActiveFilter
    ) {}
    let edges = ArrayList<DirectCall>()
    let gaps = ArrayList<CallGap>()

    private func site(node: CjSyntaxNode): NavigationTarget {
        NavigationTarget(file.fileId(db), node.textRange, node.textRange)
    }
    func gap(reason: String, node: CjSyntaxNode): Unit {
        gaps.add(CallGap(reason, site(node)))
    }

    func visit(node: CjSyntaxNode): Unit {
        db.unwindIfCancelled()
        if (!active.isActive(node)) {
            return
        }
        match (node.kind) {
            case LambdaExpr | FuncDecl => return
            case MacroExpandExpr | MacroExpandDecl =>
                gap("body-macro", node)
                return
            case CallExpr | TrailingLambdaExpr => call(node)
            case BinExpr | UnaryExpr | IndexExpr | PostfixExpr =>
                let lowered = bodyWithSourceMap(db, def)
                if (
                    let Some(expr) <- lowered
                        .sourceMap
                        .exprAtSource(BodySource(SyntaxNodePtr(node)))
                ) {
                    for (target in inferBody(db, def).calleesOf(expr)) {
                        record(target, node, "inferred-operator", ambiguous: false)
                    }
                }
                gap("implicit-operator", node)
            case MemberAccessExpr | RefExpr => value(node)
            case Interpolation => gap("implicit-conversion", node)
            case ArrayExpr | RangeExpr => gap("implicit-initialization", node)
            case ForInExpr => gap("iteration-protocol", node)
            case TryExpr => gap("resource-protocol", node)
            case SpawnExpr => gap("spawn-boundary", node)
            case _ => ()
        }
        for (child in node.children()) {
            visit(child)
        }
    }

    private func record(
        definition: DefId,
        node: CjSyntaxNode,
        resolution: String,
        ambiguous!: Bool
    ): Unit {
        let target = auditDefinition(db, definition)
        let item = itemOf(db, target) ?? return
        let virtual =
            item.has(Modifier.Open) || item.has(Modifier.Abstract) || item.has(Modifier.Override) ||
                (
                    parentOf(db, target)
                        .flatMap { parent => itemOf(db, parent) }
                        .map {
                            parent =>
                            parent.kind == ItemKind.Interface || parent.has(Modifier.Open)
                        } ??
                        false
                )
        if (virtual) {
            gap("virtual-dispatch", node)
        }
        let conservative = ambiguous || virtual
        edges.add(
            DirectCall(
                target,
                site(node),
                if (conservative) { "candidate" } else { resolution },
                isConservative: conservative
            )
        )
    }

    private func value(node: CjSyntaxNode): Unit {
        let range = calleeName(node) ?? return
        let token = tokenAt(parse(db, file).syntaxNode(), range.start) ?? return
        let definitions = classifyName(db, file, Some(def), token) ?? []
        if (definitions.isEmpty()) {
            gap("unresolved-value", node)
        }
        for (definition in definitions) {
            if (let DeclDef(target) <- definition && let Some(item) <- itemOf(db, target)) {
                if (item.kind == ItemKind.Prop || item.kind == ItemKind.Var) {
                    gap("property-or-initialization", node)
                }
            }
        }
    }

    private func call(node: CjSyntaxNode): Unit {
        let callee =
            CallExpr.cast(node).flatMap { call => call.callee() }?.syntax ??
                TrailingLambdaExpr.cast(node).flatMap { call => call.callee() }?.syntax ?? return
        let range =
            match (calleeName(callee)) {
                case Some(name) => name
                case None =>
                    gap("functional-value", node)
                    return
            }
        let definitions = callDefinitions(db, file, range.start)
        var found = false
        for (definition in definitions) {
            let target =
                match (definition) {
                    case DeclDef(decl) => auditDefinition(db, decl)
                    case _ =>
                        gap("functional-value", node);
                        continue
                }
            let item = itemOf(db, target) ?? continue
            if (
                item.kind != ItemKind.Func && item.kind != ItemKind.Init &&
                    item.kind != ItemKind.PrimaryInit &&
                    item.kind != ItemKind.EnumCtor
            ) {
                gap("functional-value-or-constructor", node)
                continue
            }
            found = true
            record(target, callee, "resolved-declaration", ambiguous: definitions.size > 1)
            if (item.kind == ItemKind.Init || item.kind == ItemKind.PrimaryInit) {
                gap("implicit-initialization", node)
            }
        }
        if (!found) {
            gap("unresolved-call", node)
        }
        // Callback invocation needs interprocedural value flow, even for a resolved declaration.
        if (
            node
                .children()
                .any {
                    child =>
                    child.kind == SyntaxKind.ArgList &&
                        child.children().any { arg => arg.kind == SyntaxKind.Arg }
                } ||
                node.kind == SyntaxKind.TrailingLambdaExpr
        ) {
            gap("callback-flow", node)
        }
    }
}
