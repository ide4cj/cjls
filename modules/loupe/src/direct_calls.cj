package loupe

import std.collection.ArrayList
import calca.*
import calca.macros.*
import cjsyntax.{CjSyntaxNode, SyntaxKind}
import cjsyntax.ast.{CallExpr, Param, TrailingLambdaExpr}
import ginkgo.SyntaxNodePtr
import loupe.db.AnalysisDatabase
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
import py_interop.*
import py_interop.internal_macros.DerivePython

/**
 * A possible immediate call. Conservative candidates are not evidence of a selected call.
 */
@DerivePython
public struct DirectCall <: Equatable<DirectCall> {
    public DirectCall(
        public let target: DefId,
        public let site: NavigationTarget,
        public let conservative: Bool,
        public let resolution: String
    ) {}
    public operator func ==(other: DirectCall): Bool {
        target == other.target && site == other.site && conservative == other.conservative &&
            resolution == other.resolution
    }
    public operator func !=(other: DirectCall): Bool {
        !(this == other)
    }
}

/**
 * A missing part of the call model; site is absent when the body itself is unavailable.
 */
@DerivePython
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
 * Empty edges prove nothing unless gaps is also empty, including in every traversed successor.
 */
@DerivePython
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
 * Canonical declaration metadata: package ownership is independent of import aliases.
 */
@DerivePython
public struct CallDeclaration {
    public CallDeclaration(
        public let definition: DefId,
        public let packageName: String,
        public let name: String,
        public let ownerName: String,
        public let location: ?NavigationTarget
    ) {}
}

private func auditPackage(db: AnalysisDatabase, definition: DefId): String {
    match (definition.file(db)) {
        case Binary(pkg, _) => pkg.name(db)
        case Source(file) => packageOfFile(db, file).map { pkg => pkg.name(db) } ?? ""
        case Expansion(call) => packageOfFile(db, call.file(db)).map { pkg => pkg.name(db) } ?? ""
        case _ => ""
    }
}

private func isTrackedMacro(db: AnalysisDatabase, resolution: Resolution): Bool {
    match (macroPathOf(db, resolution)) {
        case Some((pkg, name)) => pkg == "calca.macros" && name == "CalcaTracked"
        case None => false
    }
}

/**
 * Active written tracked declarations, resolving macro aliases by declaration ownership.
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
 * Canonical identity, ownership and optional source location of a callable.
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
 * On-demand, intraprocedural call model of the written source body. Never follows Calca's generated
 * wrapper. Nested execution boundaries are skipped, not attributed to their enclosing function.
 * See docs/direct-calls.md for the coverage contract and stable gap reason strings.
 */
@CalcaTracked
public func directCalls(db: AnalysisDatabase, def: DefId): DirectCalls {
    let file =
        match (def.file(db)) {
            case Source(source) => source
            case _ => return DirectCalls([], [CallGap("unavailable-body", None)])
        }
    let node = itemNodeOf(db, def) ?? return DirectCalls([], [CallGap("unavailable-body", None)])
    let scan = DirectCallScan(db, def, file.fileId(db), ActiveFilter.of(db, file))
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

private class DirectCallScan {
    DirectCallScan(
        let db: AnalysisDatabase,
        let def: DefId,
        let fileId: FileId,
        let active: ActiveFilter
    ) {}
    let edges = ArrayList<DirectCall>()
    let gaps = ArrayList<CallGap>()

    func site(node: CjSyntaxNode): NavigationTarget {
        NavigationTarget(fileId, node.textRange, node.textRange)
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
                        record(target, node, false, "inferred-operator")
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

    func record(definition: DefId, node: CjSyntaxNode, ambiguous: Bool, resolution: String): Unit {
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
                conservative,
                if (conservative) { "candidate" } else { resolution }
            )
        )
    }

    func value(node: CjSyntaxNode): Unit {
        let range = calleeName(node) ?? return
        let file = db.sourceFile(fileId) ?? return
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

    func call(node: CjSyntaxNode): Unit {
        let callee =
            CallExpr.cast(node).flatMap { call => call.callee() }?.syntax ??
                TrailingLambdaExpr.cast(node).flatMap { call => call.callee() }?.syntax ?? return
        let range = calleeName(callee)
        if (range.isNone()) {
            gap("functional-value", node);
            return
        }
        let file = db.sourceFile(fileId) ?? return
        let definitions = callDefinitions(db, file, range.getOrThrow().start)
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
            record(target, callee, definitions.size > 1, "resolved-declaration")
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
