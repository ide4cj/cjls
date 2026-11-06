package loupe.hir

import std.collection.*
import std.deriving.*
import calca.*
import calca.macros.*
import loupe.db.{AnalysisDatabase, Package, SourceFile}

/**
 * The syntactic member shape used to narrow a standalone lambda parameter.
 */
@Derive[Equatable, Hashable]
struct LambdaMemberShape {
    LambdaMemberShape(let name: String, let isField: Bool, let arity: Int64, let generics: Int64) {}
}

/**
 * Candidate receiver heads from the lambda's member uses. Unwritten parameters without member
 * evidence retain an empty list so ordinary arithmetic constraints can still solve them.
 */
func lambdaMemberChoices(
    db: AnalysisDatabase,
    def: DefId,
    params: Array<BodyParam>,
    block: ExprId
): Array<Array<ExtendedType>> {
    let file = sourceFileOf(db, def) ?? return Array(params.size) { _ => Array<ExtendedType>() }
    let scanner = LambdaMemberScanner(db, def, params, body(db, def), exprScopes(db, def))
    scanner.walk(block)
    Array(params.size) {
        i =>
        let shapes = scanner.shapes[i]
        if (params[i].ty.isSome() || shapes.isEmpty()) {
            return Array<ExtendedType>()
        }
        let candidates =
            lambdaOwnersWithMember(db, file, shapes[0])
                .filter {
                    owner =>
                    shapes.toArray().all { shape => lambdaHasMemberShape(db, owner, shape, file) }
                }
        if (scanner.resultShapes[i].isEmpty()) {
            let general =
                candidates
                    .filter {
                        sup =>
                        candidates.all { sub => lambdaOwnerSubtype(db, sub, sup, file) }
                    }
            if (general.size == 1) {
                return general
            }
        }
        let determined =
            candidates
                .filter {
                    owner =>
                    lambdaGenericsCovered(
                        db,
                        owner,
                        shapes.toArray(),
                        scanner.resultShapes[i],
                        file
                    )
                }
        if (!determined.isEmpty() || scanner.resultShapes[i].isEmpty()) {
            determined
        } else {
            candidates
        }
    }
}

/**
 * A package's candidate universe depends on declarations and imports, never inferred bodies.
 * Namespace imports deliberately contribute no owners: only explicitly imported declarations
 * and globs participate in the compiler's member-based inference.
 */
@CalcaTracked
func lambdaMemberOwners(db: AnalysisDatabase, pkg: Package, ofTests: Bool): Array<ExtendedType> {
    let owners = ArrayList<ExtendedType>()
    let known = HashSet<ExtendedType>()
    let add =
        {
            def: DefId =>
            if (let Some(owner) <- lambdaOwnerOf(db, def) && known.add(owner)) {
                owners.add(owner)
            }
        }
    let own = resolutionPackage(db, pkg)
    for ((_, defs) in defMap(db, own).names) {
        for (def in defs where ofTests || !isTestOf(db, own, def.id.file(db))) {
            add(def.id)
        }
    }
    lambdaImportedOwners(db, packageImportsAt(db, own, ScopeStage.Expanded, ofTests), add)
    for (file in filesOf(db, own) where ofTests || !isTestOf(db, own, file)) {
        if (let Some(source) <- scopeFileOf(db, file)) {
            lambdaImportedOwners(db, fileImports(db, pkg, source), add)
        }
    }
    let packages = ArrayList<PackageRef>([own])
    if (let Some(core) <- packageIndex(db).find("std.core", from: own) && core != own) {
        packages.add(core)
    }
    // Primitive and compiler-owned types have no ordinary declaration in source std.core.
    for (one in packages) {
        let includeTests = ofTests && one == own
        for ((owner, declarations) in packageExtends(db, one)) {
            let participates =
                declarations
                    .iterator()
                    .any { ext => includeTests || !isTestOf(db, one, ext.file(db)) }
            if (participates && known.add(owner)) {
                owners.add(owner)
            }
        }
    }
    owners.toArray()
}

/**
 * The owners with one shape, cached separately so unrelated lambda bodies share the lookup.
 */
@CalcaTracked
func lambdaOwnersWithMember(
    db: AnalysisDatabase,
    file: SourceFile,
    shape: LambdaMemberShape
): Array<ExtendedType> {
    let pkg = packageOfFile(db, file) ?? return []
    lambdaMemberOwners(db, pkg, isTestOf(db, pkg, file))
        .filter { owner => lambdaHasMemberShape(db, owner, shape, file) }
}

/**
 * Imported declarations and visible glob exports, including renamed and re-exported types.
 */
private func lambdaImportedOwners(
    db: AnalysisDatabase,
    imports: ImportedNames,
    add: (DefId) -> Unit
): Unit {
    for ((_, entries) in imports.names) {
        for (entry in entries) {
            if (let OfDecl(id) <- entry.target && !lambdaOwnerIsTest(db, id)) {
                add(id)
            }
        }
    }
    for (glob in imports.globs) {
        for ((_, defs) in packageExports(db, glob.pkg).names) {
            for (
                id in visibleOf(defs, glob.relation, glob.level) where !lambdaOwnerIsTest(db, id)
            ) {
                add(id)
            }
        }
    }
}

/**
 * A real receiver head; a type alias alone does not declare members for this search.
 */
private func lambdaOwnerOf(db: AnalysisDatabase, def: DefId): ?ExtendedType {
    match (def.item(db).kind) {
        case Class | Struct | Interface | Enum => ExtendedType.DeclType(canonicalDef(db, def))
        case BuiltIn => compilerTypeOf(db, def).map { kind => ExtendedType.BuiltInHead(kind) }
        case Extend => extendedTypeOf(db, def)
        case _ => None
    }
}

/**
 * Matches the member's category and exact written arities before trial inference. An omitted
 * method type-argument list may match a generic method; its arguments solve those variables.
 */
private func lambdaHasMemberShape(
    db: AnalysisDatabase,
    owner: ExtendedType,
    shape: LambdaMemberShape,
    file: SourceFile
): Bool {
    memberLookup(db, [owner], shape.name, from: file)
        .iterator()
        .any { member => lambdaMatchesMember(db, member, shape) }
}

/**
 * Compares receiver heads without inventing generic arguments. The ordinary body trial verifies
 * actual instantiated types; this only prefers a common declared supertype for bare member uses.
 */
private func lambdaOwnerSubtype(
    db: AnalysisDatabase,
    sub: ExtendedType,
    sup: ExtendedType,
    file: SourceFile
): Bool {
    let seen = HashSet<ExtendedType>()
    let pending = ArrayList<ExtendedType>([sub])
    var index = 0
    while (index < pending.size) {
        let current = pending[index]
        index++
        if (current == sup) {
            return true
        }
        if (!seen.add(current)) {
            continue
        }
        pending.add(all: supertypesOf(db, current))
        for (ext in extendsOf(db, current, file)) {
            pending.add(all: supertypes(db, ext))
        }
    }
    false
}

/**
 * Records only direct parameter receivers, resolving local identities so shadowed names and
 * unrelated nested parameters cannot constrain the lambda being synthesized.
 */
private class LambdaMemberScanner {
    let shapes: Array<ArrayList<LambdaMemberShape>>
    let resultShapes: Array<HashSet<LambdaMemberShape>>

    LambdaMemberScanner(
        private let db: AnalysisDatabase,
        private let def: DefId,
        private let params: Array<BodyParam>,
        private let hir: Body,
        private let scopes: ExprScopes
    ) {
        shapes = Array(params.size) { _ => ArrayList<LambdaMemberShape>() }
        resultShapes = Array(params.size) { _ => HashSet<LambdaMemberShape>() }
    }

    func walk(root: ExprId): Unit {
        let pending = ArrayList<(ExprId, Bool)>([(root, false)])
        var index = 0
        while (index < pending.size) {
            let (expr, constrained) = pending[index]
            index++
            match (hir[expr]) {
                case BinaryExpr(_, lhs, rhs) => pending.add(all: [(lhs, true), (rhs, true)])
                case IsExpr(inner, _) => pending.add((inner, true))
                case AsExpr(inner, _) => pending.add((inner, true))
                case CallExpr(callee, args) =>
                    if (
                        let FieldExpr(receiver, name, generics) <- hir[callee] &&
                            record(
                                receiver,
                                LambdaMemberShape(name, false, args.size, generics.size),
                                constrained: constrained
                            )
                    ) {
                        pending.add(all: args.map { arg => (arg.expr, constrained) })
                    } else {
                        pending.add((callee, constrained))
                        pending.add(all: args.map { arg => (arg.expr, constrained) })
                    }
                case IndexExpr(receiver, indices) =>
                    record(
                        receiver,
                        LambdaMemberShape("[]", false, indices.size, 0),
                        constrained: constrained
                    )
                    pending.add((receiver, constrained))
                    pending.add(all: indices.map { one => (one, constrained) })
                case FieldExpr(receiver, name, _) =>
                    record(receiver, LambdaMemberShape(name, true, 0, 0), constrained: constrained)
                    pending.add((receiver, constrained))
                case _ => pending.add(all: children(expr).map { one => (one, constrained) })
            }
        }
    }

    private func record(receiver: ExprId, shape: LambdaMemberShape, constrained!: Bool): Bool {
        let name =
            match (hir[receiver]) {
                case PathExpr(name, _) => name
                case _ => return false
            }
        let targets =
            match (resolveBodyName(db, def, scopes.scopeOf(receiver), name)) {
                case Values(targets) => targets
                case _ => return false
            }
        if (targets.size != 1) {
            return false
        }
        let local =
            match (targets[0]) {
                case LocalOf(local) => local
                case _ => return false
            }
        for (i in 0..params.size where params[i].local == Some(local) && params[i].ty.isNone()) {
            if (!shapes[i].contains(shape)) {
                shapes[i].add(shape)
            }
            if (constrained) {
                resultShapes[i].add(shape)
            }
            return true
        }
        false
    }

    private func children(expr: ExprId): Array<ExprId> {
        match (hir[expr]) {
            case BlockExpr(stmts) =>
                stmts
                    .flatMap {
                        stmt =>
                        match (stmt) {
                            case LetStmt(_, _, value) => value.map { one => [one] } ?? []
                            case ExprStmt(one) => [one]
                            case FuncStmt(i) => hir.funcs[i].body.map { one => [one] } ?? []
                        }
                    }
            case StrExpr(parts) => parts
            case QuoteExpr(parts) => parts
            case TupleExpr(parts) => parts
            case ArrayExpr(parts) => parts
            case UnaryExpr(_, inner) => [inner]
            case ConvExpr(_, inner) => [inner]
            case PostfixExpr(inner, _, value) => [inner].concat(value.map { one => [one] } ?? [])
            case AssignedExpr(_, _, value) => [value]
            case RangeExpr(start, end, step, _) =>
                [start, end, step].flatMap { value => value.map { one => [one] } ?? [] }
            case IfExpr(condition, then, otherwise) =>
                [condition, then].concat(otherwise.map { one => [one] } ?? [])
            case LetExpr(_, value) => [value]
            case MatchExpr(value, arms) =>
                (value.map { one => [one] } ?? []).concat(armChildren(arms))
            case QuestMatchExpr(value, arms) => [value].concat(armChildren(arms))
            case TryExpr(resources, tried, catches, finallyBlock) =>
                resources
                    .map { resource => resource.value }
                    .concat([tried])
                    .concat(catches.map { arm => arm.body })
                    .concat(finallyBlock.map { one => [one] } ?? [])
            case ForExpr(_, iterated, guard, loopBody) =>
                [iterated, loopBody].concat(guard.map { one => [one] } ?? [])
            case WhileExpr(condition, loopBody) => [condition, loopBody]
            case DoWhileExpr(loopBody, condition) => [loopBody, condition]
            case ThrowExpr(inner) => [inner]
            case ReturnExpr(value) => value.map { one => [one] } ?? []
            case SpawnExpr(context, lambda) => (context.map { one => [one] } ?? []).concat([lambda])
            case SynchronizedExpr(lock, block) => [lock, block]
            case UnsafeExpr(block) => [block]
            case LambdaExpr(_, block) => [block]
            case MacroExpr(call) => call.args.map { arg => arg.expr }
            case _ => []
        }
    }

    private func armChildren(arms: Array<MatchArm>): Array<ExprId> {
        arms
            .flatMap {
                arm =>
                [arm.body].concat(
                    [arm.guard, arm.condition].flatMap { value => value.map { one => [one] } ?? [] }
                )
            }
    }
}

/**
 * Prunes generic owners whose arguments cannot be determined from these member usages.
 * Results contribute only beneath a binary, is or as expression; a bare generic field alone
 * does not supply any constraints. Inherited and extended member types are viewed on the owner
 * before collecting its parameters, preserving the actual generic substitution.
 */
private func lambdaGenericsCovered(
    db: AnalysisDatabase,
    owner: ExtendedType,
    shapes: Array<LambdaMemberShape>,
    constrained: HashSet<LambdaMemberShape>,
    file: SourceFile
): Bool {
    let head =
        match (owner) {
            case DeclType(id) => id
            case _ => return true
        }
    let count = genericsOf(db, head).size
    if (count == 0) {
        return true
    }
    let covered = HashSet<Int64>()
    let recv = selfTyOf(db, head)
    for (shape in shapes) {
        for (
            target in memberLookup(db, [owner], shape.name, from: file) where lambdaMatchesMember(
                db,
                target,
                shape
            )
        ) {
            match (target) {
                case MemberDecl(id) =>
                    let sig = signatureTypes(db, id)
                    let types = sig
                        .params
                        .concat(
                            if (constrained.contains(shape)) {
                                sig.ty.map { one => [one] } ?? []
                            } else {
                                []
                            }
                        )
                    for (ty in types) {
                        lambdaCoverType(db, asMemberOf(db, ty, id, recv, file) ?? ty, head, covered)
                    }
                case MemberParam(ctor, local) where constrained.contains(shape) =>
                    let params = body(db, ctor).params
                    let sig = signatureTypes(db, ctor)
                    for (i in 0..params.size where params[i].local == Some(local)) {
                        if (let Some(ty) <- sig.params.get(i)) {
                            lambdaCoverType(
                                db,
                                asMemberOf(db, ty, ctor, recv, file) ?? ty,
                                head,
                                covered
                            )
                        }
                    }
                case _ => ()
            }
        }
    }
    covered.size == count
}

/**
 * Collects one owner's parameters occurring structurally in a member's substituted type.
 */
private func lambdaCoverType(
    db: AnalysisDatabase,
    ty: Ty,
    owner: DefId,
    covered: HashSet<Int64>
): Unit {
    let pending = ArrayList<Ty>([ty])
    var index = 0
    while (index < pending.size) {
        let one = pending[index]
        index++
        match (one.kind(db)) {
            case ParamTy(GenericOwner.Declaration(head), i) where canonicalDef(db, head) == owner =>
                covered.add(i)
            case DeclTy(_, args) => pending.add(all: args)
            case BuiltInTy(_, args) => pending.add(all: args)
            case TupleTy(args) => pending.add(all: args)
            case FuncTy(params, ret, _) => pending.add(all: params.concat([ret]))
            case VArrayTy(element, _) => pending.add(element)
            case _ => ()
        }
    }
}

/**
 * Whether this target has the category and exact arities of one syntactic use.
 */
private func lambdaMatchesMember(
    db: AnalysisDatabase,
    member: MemberTarget,
    shape: LambdaMemberShape
): Bool {
    match (member) {
        case MemberParam(_, _) => shape.isField
        case MemberDecl(id) =>
            let kind = id.item(db).kind
            if (shape.isField) {
                kind == ItemKind.Var || kind == ItemKind.Prop
            } else if (kind == ItemKind.Func) {
                let sig = signatureTypes(db, id)
                sig.params.size == shape.arity &&
                    (shape.generics == 0 || sig.generics.size == shape.generics)
            } else {
                false
            }
    }
}

/**
 * Dependency tests are never imported into another package's candidate universe.
 */
private func lambdaOwnerIsTest(db: AnalysisDatabase, def: DefId): Bool {
    let pkg = packageRefOf(db, def) ?? return false
    isTestOf(db, pkg, def.file(db))
}
