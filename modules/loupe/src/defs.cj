package loupe

import std.collection.*
import std.deriving.*
import ginkgo.SyntaxNodePtr
import cjsyntax.{CjSyntaxNode, CjSyntaxToken}
import cjsyntax.ast.{BindPat, EnumPat, MacroExpandDecl, MacroExpandExpr, MemberAccessExpr, NameRef, PathSegment,
    RefExpr}
import loupe.db.{AnalysisDatabase, SourceFile}
import loupe.hir.*

/**
 * What a name means, rust-analyzer's `Definition`: what go to definition goes to, and what highlighting tells a
 * name by.
 */
@Derive[Equatable]
public enum Definition <: ToString {
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
}

/**
 * What the name `token`, of `file`, means, `item` the innermost item it is in: a name in a type of a signature (D48)
 * or of a body, a name a body uses, a constructor a pattern names (D50), a member after a `.` of a package, a type
 * (D52) or a value (D55), the macro of a call or a package before it; each candidate of an ambiguity or of an
 * overload not taken, the one a call takes. Empty when it means nothing; `None` when the name is none of those, or
 * nothing tells yet what it is: a member of a value of a type not inferred, a constructor named by a path.
 */
func classifyName(db: AnalysisDatabase, file: SourceFile, item: ?DefId, token: CjSyntaxToken): ?Array<Definition> {
    if (let Some(ofMacro) <- macroDefinitions(db, file, token)) {
        return ofMacro
    }
    let def = item ?? return None
    if (let Some((typeNode, segment)) <- typeAt(token)) {
        return typeDefinitions(db, def, typeNode, segment)
    }
    bodyDefinitions(db, def, token)
}

/**
 * What a segment of the name of a macro call means, if `token` is one: a macro of the file's scope, whatever item the
 * call is on or in, a macro being no local; a package before it.
 */
func macroDefinitions(db: AnalysisDatabase, file: SourceFile, token: CjSyntaxToken): ??Array<Definition> {
    let name = NameRef.cast(token.parent) ?? return None
    let call = name.syntax.parent ?? return None
    let names = match ((MacroExpandDecl.cast(call), MacroExpandExpr.cast(call))) {
        case (Some(decl), _) => decl.nameRefs() |> collectArray
        case (_, Some(expr)) => expr.nameRefs() |> collectArray
        case _ => return None
    }
    // A segment of a macro's name is nothing else: a file of no package leaves it unknown, not to the lookups below.
    let pkg = packageOfFile(db, file) ?? return Some(None)
    let segment = names.map {one => one.syntax.textRange}.indexOf(name.syntax.textRange) ?? return Some(None)
    let resolved = resolveMacroPath(db, pkg, file, names.map {one => one.text()})
    Some(fileDefinitions(resolved[segment]))
}

/**
 * What the segment `segment` of the type `typeNode`, in the signature or the body of `def`, names.
 */
func typeDefinitions(db: AnalysisDatabase, def: DefId, typeNode: CjSyntaxNode, segment: Int64): ?Array<Definition> {
    let ptr = SyntaxNodePtr(typeNode)
    let lowered = signatureWithSourceMap(db, def)
    let (ty, resolve) = match (lowered.sourceMap.typeAt(ptr)) {
        // as lowering resolved it, if it did
        case Some(ty) => (lowered.signature[ty], {
            path: Array<String> => signatureTypes(db, def).pathOf(ty) ??
                resolveTypePath(db, typeScopeOf(db, def) ?? return Array<PathResolution>(), path)
        })
        case None =>
            let lowered = bodyWithSourceMap(db, def)
            let ty = lowered.sourceMap.typeAt(ptr) ?? return None
            (lowered.body.types[ty.index], {
                path: Array<String> => inferBody(db, def).typePathOf(ty) ?? resolveBodyTypePath(db, def, ty, path)
            })
    }
    match (ty) {
        case PathRef(segments) => match (resolve(segments.map {one => one.name}).get(segment)) {
            case Some(Resolved(target)) => [typeDefinition(target)]
            case Some(AmbiguousPath(targets)) => targets.map {target => scopeDefinition(target)}
            case Some(ConflictedPackages(pkgs)) => pkgs.map {pkg => Definition.PackageDef(pkg)}
            case Some(UnresolvedPath) => []
            case None => None
        }
        case ThisRef => match (parentOf(db, def)) {
            case Some(parent) where parent.item(db).kind == ItemKind.Class => [Definition.DeclDef(parent)]
            case _ => []
        }
        case _ => None
    }
}

/**
 * What the name `token`, in the body of `def`, means: what a name used there means (N59–N71), what a name after a
 * `.` does (N75–N79), the constructor a pattern names (N72), a local itself at its declaration.
 */
func bodyDefinitions(db: AnalysisDatabase, def: DefId, token: CjSyntaxToken): ?Array<Definition> {
    let name = token.parent
    let node = name.parent ?? return None
    let lowered = bodyWithSourceMap(db, def)
    let sourceMap = lowered.sourceMap
    let pkg = match (def.file(db)) {
        case Source(file) => packageOfFile(db, file) ?? return None
        case _ => return None
    }
    // an operator: the operator function it calls (8e)
    if (isOperator(token)) {
        let expr = sourceMap.exprAt(SyntaxNodePtr(token.parent)) ?? return None
        return match (inferBody(db, def).calleeOf(expr)) {
            case Some(decl) => [Definition.DeclDef(decl)]
            case None => []
        }
    }
    if (let Some(ref) <- RefExpr.cast(node)) {
        let expr = sourceMap.exprAt(SyntaxNodePtr(ref.syntax)) ?? return None
        let inferred = inferBody(db, def)
        // of overloads, the one inference chose (8d)
        if (let Some(decl) <- inferred.calleeOf(expr)) {
            return [Definition.DeclDef(decl)]
        }
        let resolution = inferred.nameOf(expr) ?? resolveBodyName(db, def, exprScopes(db, def).scopeOf(expr),
            token.text())
        return match (resolution) {
            case Values(targets) => targets.map {target => valueDefinition(def, target)}
            case InFile(resolution) => fileDefinitions(resolution)
        }
    }
    if (let Some(access) <- MemberAccessExpr.cast(node)) {
        let expr = sourceMap.exprAt(SyntaxNodePtr(access.syntax)) ?? return None
        let inferred = inferBody(db, def)
        if (let Some(decl) <- inferred.calleeOf(expr)) {
            return [Definition.DeclDef(decl)]
        }
        return match (inferred.accessOf(expr) ?? resolveField(db, def, expr)) {
            case PackageMembers(ids) => ids.map {id => Definition.DeclDef(id)}
            case TypeMembers(targets) => targets.map {target => memberDefinition(target)}
            // a member of a value: what its type has (D55), nothing if it is not known
            case OfValue => inferred.fieldOf(expr).map {
                targets => targets.map {target => memberDefinition(target)}
            }
            case NoField => []
        }
    }
    if (let Some(_) <- BindPat.cast(node)) {
        let local = sourceMap.localAt(SyntaxNodePtr(name)) ?? return None
        let ctors = if (lowered.body[local].lone) {
            ctorsNamed(db, pkg, token.text())
        } else {
            Array<DefId>()
        }
        return if (ctors.isEmpty()) {
            [Definition.LocalDef(def, local)]
        } else {
            ctors.map {id => Definition.DeclDef(id)}
        }
    }
    if (let Some(segment) <- PathSegment.cast(node)) {
        let pat = segment.syntax.parent.flatMap {one => EnumPat.cast(one)} ?? return None
        if ((pat.pathSegments() |> collectArray).size == 1) {
            return ctorsNamed(db, pkg, token.text()).map {id => Definition.DeclDef(id)}
        }
        return None
    }
    let local = sourceMap.localAt(SyntaxNodePtr(name)) ?? return None
    [Definition.LocalDef(def, local)]
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
        case Found(ids) => ids.map {id => Definition.DeclDef(id)}
        case FoundPackage(pkg) => [Definition.PackageDef(pkg)]
        case Ambiguous(targets) => targets.map {target => scopeDefinition(target)}
        case Ctors(own, imported) => own.concat(imported).map {id => Definition.DeclDef(id)}
        case NotFound => []
    }
}
