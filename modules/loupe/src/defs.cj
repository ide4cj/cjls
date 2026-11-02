package loupe

import std.collection.*
import cjsyntax.{CjSyntaxNode, CjSyntaxToken, SyntaxKind}
import cjsyntax.ast.{
    Arg,
    BindPat,
    EnumPat,
    MacroExpandDecl,
    MacroExpandExpr,
    MemberAccessExpr,
    NameRef,
    PathSegment,
    RefExpr
}
import ginkgo.SyntaxNodePtr
import loupe.db.{AnalysisDatabase, Package, SourceFile}
import loupe.hir.*
import py_interop.*
import py_interop.internal_macros.DerivePython

/**
 * What a name means, rust-analyzer's `Definition`: what go to definition goes to, and what highlighting tells a
 * name by.
 */
@DerivePython
public enum Definition <: ToString & Equatable<Definition> {
    /**
     * A declaration, of a source or of a package compiled already.
     */
    | DeclDef(DefId)
    /**
     * A local of the body of a declaration.
     */
    | LocalDef(DefId, LocalId)
    /**
     * A `let` or `var` parameter of a primary constructor, a member as well (N69): the constructor, and the
     * parameter's local in its body.
     */
    | MemberParamDef(DefId, LocalId)
    /**
     * A type parameter: of a declaration, or of a function a body declares.
     */
    | TypeParamDef(TypeTarget)
    /**
     * A package, by the name it is imported by.
     */
    | PackageDef(PackageRef)

    public func toString(): String {
        match (this) {
            case DeclDef(id) => id.toString()
            case LocalDef(def, local) => "local ${local} of ${def}"
            case MemberParamDef(ctor, local) => "member ${local} of ${ctor}"
            case TypeParamDef(target) => target.toString()
            case PackageDef(pkg) => "package ${pkg}"
        }
    }

    public operator func ==(other: Definition): Bool {
        match ((this, other)) {
            case (Definition.DeclDef(left0), Definition.DeclDef(right0)) => left0 == right0
            case (Definition.LocalDef(left0, left1), Definition.LocalDef(right0, right1)) =>
                left0 == right0 && left1 == right1
            case (
                    Definition.MemberParamDef(left0, left1),
                    Definition.MemberParamDef(right0, right1)
                ) => left0 == right0 && left1 == right1
            case (Definition.TypeParamDef(left0), Definition.TypeParamDef(right0)) =>
                left0 == right0
            case (Definition.PackageDef(left0), Definition.PackageDef(right0)) => left0 == right0
            case _ => false
        }
    }

    public operator func !=(other: Definition): Bool {
        !(this == other)
    }
}

/**
 * A specialized name lookup: whether the token belongs to its context, and, if it does, whether
 * its meaning is known. An empty `NameDefinitions` means the name resolves to nothing.
 */
enum NameClassification {
    | NotApplicable
    | UnknownMeaning
    | NameDefinitions(Array<Definition>)
}

/**
 * What the name `token`, of `file`, means, `item` the innermost item it is in: a name in a type of a signature (D48)
 * or of a body, a name a body uses, a constructor a pattern names (D50), a member after a `.` of a package, a type
 * (D52) or a value (D55), the macro of a call or a package before it; each candidate of an ambiguity or of an
 * overload not taken, the one a call takes. Empty when it means nothing; `None` when the name is none of those, or
 * nothing tells yet what it is: a member of a value of a type not inferred, a constructor named by a path.
 */
func classifyName(
    db: AnalysisDatabase,
    file: SourceFile,
    item: ?DefId,
    token: CjSyntaxToken,
    expansion!: ?MacroCallId = None
): ?Array<Definition> {
    match (macroDefinitions(db, file, token)) {
        case NotApplicable => ()
        case UnknownMeaning => return None
        case NameDefinitions(defs) => return defs
    }
    match (importDefinitions(db, file, token)) {
        case NotApplicable => ()
        case UnknownMeaning => return None
        case NameDefinitions(defs) => return defs
    }
    let def = item ?? return None
    if (let Some((typeNode, segment)) <- typeAt(token)) {
        return typeDefinitions(db, def, typeNode, segment, expansion: expansion)
    }
    bodyDefinitions(db, def, token, expansion: expansion)
}

/**
 * What a segment of the name of a macro call means, if `token` is one: a macro of the file's scope, whatever item the
 * call is on or in, a macro being no local; a package before it.
 */
func macroDefinitions(
    db: AnalysisDatabase,
    file: SourceFile,
    token: CjSyntaxToken
): NameClassification {
    let name = NameRef.cast(token.parent) ?? return NotApplicable
    let call = name.syntax.parent ?? return NotApplicable
    let (names, hasAttr, onDecl) =
        match ((MacroExpandDecl.cast(call), MacroExpandExpr.cast(call))) {
            case (Some(decl), _) =>
                (decl.nameRefs() |> collectArray, decl.macroAttr().isSome(), true)
            case (_, Some(expr)) =>
                (expr.nameRefs() |> collectArray, expr.macroAttr().isSome(), false)
            case _ => return NotApplicable
        }
    // A segment of a macro's name is nothing else: a file of no package leaves it unknown, not to the lookups below.
    let pkg = packageOfFile(db, file) ?? return UnknownMeaning
    let segment =
        names.map { one => one.syntax.textRange }.indexOf(name.syntax.textRange) ??
            return UnknownMeaning
    let path = names.map { one => one.text() }
    let resolved = fileDefinitions(resolveMacroPath(db, pkg, file, path)[segment])
    if (segment < names.size - 1) {
        return NameDefinitions(resolved)
    }
    if (resolved.isEmpty() && onDecl) {
        return NameDefinitions(annotationDefinitions(db, pkg, file, path))
    }
    NameDefinitions(macrosCalled(db, resolved, hasAttr))
}

/**
 * The class a call of no macro on a declaration names: an annotation of its own (`@A[1]` of an `@Annotation class
 * A`), which the parser does not tell from a macro call, going, as `A(1)` does, to the class. Nothing if `path`'s
 * last segment names no class.
 */
func annotationDefinitions(
    db: AnalysisDatabase,
    pkg: Package,
    file: SourceFile,
    path: Array<String>
): Array<Definition> {
    match (resolveTypePath(db, TypeScope([], pkg, file), path).get(path.size - 1)) {
        case Some(Resolved(TypeOf(id))) where id.item(db).kind == ItemKind.Class =>
            [Definition.DeclDef(id)]
        case _ => []
    }
}

/**
 * Of the macros `defs` of one name, those a call runs: one with an attribute the macro of two parameters, one
 * without the macro of one, as cjc's `macroCall_a_` and `macroCall_c_`; all of them if none is.
 */
func macrosCalled(db: AnalysisDatabase, defs: Array<Definition>, hasAttr: Bool): Array<Definition> {
    let params = if (hasAttr) { 2 } else { 1 }
    let called =
        defs
            .filter {
                one =>
                match (one) {
                    case DeclDef(id) => signatureTypes(db, id).params.size == params
                    case _ => false
                }
            }
    if (called.isEmpty()) { defs } else { called }
}

/**
 * What a name of an `import` means, if `token` is one: the name a leaf brings (its last, or its alias), what the leaf
 * imports, each declaration of the name or the package (N5–N10); a name before it, the package the path names up to
 * it, if one.
 */
func importDefinitions(
    db: AnalysisDatabase,
    file: SourceFile,
    token: CjSyntaxToken
): NameClassification {
    let (path, isLeaf) = importPathTo(token.parent) ?? return NotApplicable
    let pkg = packageOfFile(db, file) ?? return NameDefinitions([])
    let from = PackageRef.Source(pkg)
    let ofTests = isTestOf(db, pkg, file)
    if (isLeaf) {
        return NameDefinitions(
            match (resolveImport(db, from, path, Visibility.Private, ofTests: ofTests)) {
                case ToPackage(_, target) => [Definition.PackageDef(target)]
                case ToNames(_, names) =>
                    names.values() |> flatMap { ids: Array<DefId> => ids } |>
                        map { id: DefId => Definition.DeclDef(id) } |>
                        collectArray
                case Unresolved(_) => []
            }
        )
    }
    NameDefinitions(
        match (
            packageIndex(db)
                .find(String.join(path.segments, delimiter: "."), from: from, ofTests: ofTests)
        ) {
            case Some(target) => [Definition.PackageDef(target)]
            case None => []
        }
    )
}

/**
 * What the segment `segment` of the type `typeNode`, in the signature or the body of `def`, names.
 */
func typeDefinitions(
    db: AnalysisDatabase,
    def: DefId,
    typeNode: CjSyntaxNode,
    segment: Int64,
    expansion!: ?MacroCallId = None
): ?Array<Definition> {
    let ptr = SyntaxNodePtr(typeNode)
    let lowered = signatureWithSourceMap(db, def)
    let (ty, resolve) =
        match (if (expansion.isNone()) { lowered.sourceMap.typeAt(ptr) } else { None<TypeRefId> }) {
            // as lowering resolved it, if it did
            case Some(ty) =>
                (
                    lowered.signature[ty],
                    {
                        path: Array<String> =>
                        signatureTypes(db, def).pathOf(ty) ??
                            resolveTypePath(
                                db,
                                typeScopeOf(db, def) ?? return Array<PathResolution>(),
                                path
                            )
                    }
                )
            case None =>
                let lowered = bodyWithSourceMap(db, def)
                let ty =
                    lowered.sourceMap.typeAtSource(BodySource(ptr, expansion: expansion)) ??
                        return None
                (
                    lowered.body.types[ty.index],
                    {
                        path: Array<String> =>
                        inferBody(db, def).typePathOf(ty) ?? resolveBodyTypePath(db, def, ty, path)
                    }
                )
        }
    match (ty) {
        case PathRef(segments) =>
            match (resolve(segments.map { one => one.name }).get(segment)) {
                case Some(Resolved(target)) => [typeDefinition(target)]
                case Some(AmbiguousPath(targets)) =>
                    targets.map { target => scopeDefinition(target) }
                case Some(ConflictedPackages(pkgs)) =>
                    pkgs.map { pkg => Definition.PackageDef(pkg) }
                case Some(UnresolvedPath) => []
                case None => None
            }
        case ThisRef =>
            match (parentOf(db, def)) {
                case Some(parent) where parent.item(db).kind == ItemKind.Class =>
                    [Definition.DeclDef(parent)]
                case _ => []
            }
        case _ => None
    }
}

/**
 * The node of a name after a `.` whose parent `node` is: `a.b`, or `k: v` in a macro's `[...]`, `@Configure`'s option
 * `KeyK.k` (#191).
 */
func accessNodeOf(node: CjSyntaxNode): ?CjSyntaxNode {
    if (MemberAccessExpr.canCast(node.kind)) {
        return node
    }
    if (
        Arg.canCast(node.kind) && node.parent.map { one => one.kind } == Some(SyntaxKind.MacroAttr)
    ) {
        return node
    }
    None
}

/**
 * What the name `token`, in the body of `def`, means: what a name used there means (N59–N71), what a name after a
 * `.` does (N75–N79), the constructor a pattern names (N72), a local itself at its declaration.
 */
func bodyDefinitions(
    db: AnalysisDatabase,
    def: DefId,
    token: CjSyntaxToken,
    expansion!: ?MacroCallId = None
): ?Array<Definition> {
    let name = token.parent
    let node = name.parent ?? return None
    let lowered = bodyWithSourceMap(db, def)
    let sourceMap = lowered.sourceMap
    let file = scopeFileOf(db, def.file(db)) ?? return None
    let pkg = packageOfFile(db, file) ?? return None
    // an operator: the operator function it calls (8e); `+=` of `a[i] += v` its `+` and the `[]` taking a value (#245)
    if (isOperator(token)) {
        let expr =
            sourceMap.exprAtSource(BodySource(SyntaxNodePtr(token.parent), expansion: expansion)) ??
                return None
        return inferBody(db, def).calleesOf(expr).map { decl => Definition.DeclDef(decl) }
    }
    if (name.kind == SyntaxKind.ThisExpr || name.kind == SyntaxKind.SuperExpr) {
        let expr =
            sourceMap.exprAtSource(BodySource(SyntaxNodePtr(name), expansion: expansion)) ??
                return None
        return inferBody(db, def).calleesOf(expr).map { decl => Definition.DeclDef(decl) }
    }
    if (let Some(ref) <- RefExpr.cast(node)) {
        let expr =
            sourceMap.exprAtSource(BodySource(SyntaxNodePtr(ref.syntax), expansion: expansion)) ??
                return None
        let inferred = inferBody(db, def)
        // of overloads, the one inference chose (8d)
        if (let Some(decl) <- inferred.calleeOf(expr)) {
            return [Definition.DeclDef(decl)]
        }
        let resolution =
            inferred.nameOf(expr) ??
                resolveBodyName(db, def, exprScopes(db, def).scopeOf(expr), token.text())
        return resolutionDefinitions(def, resolution)
    }
    if (let Some(access) <- accessNodeOf(node)) {
        let expr =
            sourceMap.exprAtSource(BodySource(SyntaxNodePtr(access), expansion: expansion)) ??
                return None
        let inferred = inferBody(db, def)
        if (let Some(decl) <- inferred.calleeOf(expr)) {
            return [Definition.DeclDef(decl)]
        }
        return match (inferred.accessOf(expr) ?? resolveField(db, def, expr)) {
            case PackageMembers(ids) => ids.map { id => Definition.DeclDef(id) }
            case TypeMembers(targets) => targets.map { target => memberDefinition(target) }
            // a member of a value: what its type has (D55), nothing if it is not known
            case OfValue =>
                inferred
                    .fieldOf(expr)
                    .map { targets => targets.map { target => memberDefinition(target) } }
            case NoField => []
        }
    }
    if (let Some(_) <- BindPat.cast(node)) {
        let local =
            sourceMap.localAtSource(BodySource(SyntaxNodePtr(name), expansion: expansion)) ??
                return None
        let ctors =
            if (lowered.body[local].lone) {
                ctorsNamed(db, pkg, file, token.text())
            } else {
                Array<DefId>()
            }
        return if (ctors.isEmpty()) {
            [Definition.LocalDef(def, local)]
        } else {
            ctors.map { id => Definition.DeclDef(id) }
        }
    }
    if (let Some(segment) <- PathSegment.cast(node)) {
        let pat = segment.syntax.parent.flatMap { one => EnumPat.cast(one) } ?? return None
        if ((pat.pathSegments() |> collectArray).size == 1) {
            return ctorsNamed(db, pkg, file, token.text()).map { id => Definition.DeclDef(id) }
        }
        return None
    }
    let local =
        sourceMap.localAtSource(BodySource(SyntaxNodePtr(name), expansion: expansion)) ??
            return None
    [Definition.LocalDef(def, local)]
}

/**
 * What a plain name of the body of `def` means, as `resolution`, what it resolved to, says.
 */
func resolutionDefinitions(def: DefId, resolution: BodyResolution): Array<Definition> {
    match (resolution) {
        case Values(targets) => targets.map { target => valueDefinition(def, target) }
        case InFile(resolution) => fileDefinitions(resolution)
    }
}

func valueDefinition(def: DefId, target: ValueTarget): Definition {
    match (target) {
        case LocalOf(local) => Definition.LocalDef(def, local)
        case MemberOf(member) => memberDefinition(member)
        case DeclOf(id) => Definition.DeclDef(id)
        case TypeParamOf(typeTarget) => typeDefinition(typeTarget)
    }
}

func memberDefinition(target: MemberTarget): Definition {
    match (target) {
        case MemberDecl(id) => Definition.DeclDef(id)
        case MemberParam(ctor, local) => Definition.MemberParamDef(ctor, local)
    }
}

func typeDefinition(target: TypeTarget): Definition {
    match (target) {
        case TypeOf(id) => Definition.DeclDef(id)
        case QualifierOf(pkg) => Definition.PackageDef(pkg)
        case _ => Definition.TypeParamDef(target)
    }
}

func scopeDefinition(target: ScopeTarget): Definition {
    match (target) {
        case OfDecl(id) => Definition.DeclDef(id)
        case OfPackage(pkg) => Definition.PackageDef(pkg)
    }
}

/**
 * What the file's scope has: its declarations, its constructors, a package.
 */
func fileDefinitions(resolution: Resolution): Array<Definition> {
    match (resolution) {
        case Found(ids) => ids.map { id => Definition.DeclDef(id) }
        case FoundPackage(pkg) => [Definition.PackageDef(pkg)]
        case Ambiguous(targets) => targets.map { target => scopeDefinition(target) }
        case Ctors(own, imported) => own.concat(imported).map { id => Definition.DeclDef(id) }
        case NotFound => []
    }
}
