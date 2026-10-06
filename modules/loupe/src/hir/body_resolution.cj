package loupe.hir

import std.collection.*
import std.deriving.*
import loupe.db.{AnalysisDatabase, Package, SourceFile}

/**
 * What a name used in a body stands for.
 */
@Derive[Equatable]
public enum ValueTarget <: ToString {
    /**
     * A local of the body.
     */
    | LocalOf(LocalId)
    /**
     * A member of the type the body is in (N69).
     */
    | MemberOf(MemberTarget)
    /**
     * A declaration of the file's scope.
     */
    | DeclOf(DefId)
    /**
     * A type parameter, through which a static member is reached (`T.make()`, N74).
     */
    | TypeParamOf(TypeTarget)

    public func toString(): String {
        match (this) {
            case LocalOf(local) => "local ${local}"
            case MemberOf(member) => "member ${member}"
            case DeclOf(id) => id.toString()
            case TypeParamOf(target) => target.toString()
        }
    }
}

/**
 * What a name used in a body means.
 */
@Derive[Equatable]
public enum BodyResolution <: ToString {
    /**
     * A local or a member, or functions overloading one another over the levels: local, then
     * members, then the file's (N63, N70).
     */
    | Values(Array<ValueTarget>)
    /**
     * Neither a local nor a member has it: what the file's scope says.
     */
    | InFile(Resolution)

    public func toString(): String {
        match (this) {
            case Values(targets) => "values ${targets}"
            case InFile(resolution) => "in file ${resolution}"
        }
    }
}

/**
 * The source file and the package of `def`, if it is a source declaration of the project.
 */
func sourceOf(db: AnalysisDatabase, def: DefId): ?(Package, SourceFile) {
    let file = match (def.file(db)) {
        case Source(file) => file
        case Binary(_, _) => return None
    }
    let pkg = packageOfFile(db, file) ?? return None
    (pkg, file)
}

/**
 * The constructors named `name` a pattern of `pkg` may mean: those of the enums of the package, and
 * of those any of its files imports (N72, N73).
 */
public func ctorsNamed(db: AnalysisDatabase, pkg: Package, name: String): Array<DefId> {
    let found = ArrayList<DefId>()
    for (def in defMap(db, PackageRef.Source(pkg)).ctors.get(name) ?? []) {
        found.add(def.id)
    }
    for (id in packageCtorImports(db, pkg).named(db, name) where !found.contains(id)) {
        found.add(id)
    }
    found.toArray()
}

/**
 * What `name`, used as a value at the scope `scope` of the body of `def`, means: the locals from
 * `scope` out, the nearest that is no function deciding, functions gathering, a local function's
 * type parameters in its own; then the type parameters of `def`; the members of the type the body
 * is in; that type's type parameters; the file's scope (N60–N63, N69, N70, N74). A pattern's lone
 * name is no local if a constructor has it (N72).
 */
public func resolveBodyName(db: AnalysisDatabase, def: DefId, scope: ?ScopeId, name: String): BodyResolution {
    let (pkg, file) = sourceOf(db, def) ?? return BodyResolution.InFile(Resolution.NotFound)
    let lowered = body(db, def)
    let scopes = exprScopes(db, def)
    let funcs = ArrayList<ValueTarget>()
    // what is no function decides, but for the functions found before it
    let settle = {
        target: ValueTarget => BodyResolution.Values(if (funcs.isEmpty()) {
            [target]
        } else {
            funcs.toArray()
        })
    }
    var isCtor: ?Bool = None
    for (one in scopes.chain(scope)) {
        for (local in scopes[one].entries where lowered[local].name == name) {
            if (lowered[local].lone) {
                let ctor = isCtor ?? !ctorsNamed(db, pkg, name).isEmpty()
                isCtor = ctor
                if (ctor) {
                    continue
                }
            }
            if (lowered[local].kind != LocalKind.FuncLocal) {
                return settle(ValueTarget.LocalOf(local))
            }
            funcs.add(ValueTarget.LocalOf(local))
        }
        let data = scopes[one]
        if (let Some(index) <- data.genericsOf) {
            for (i in 0..data.generics.size where data.generics[i] == name) {
                return settle(ValueTarget.TypeParamOf(TypeTarget.LocalGenericOf(def, index, i)))
            }
        }
    }
    let own = signature(db, def).generics
    for (i in 0..own.size where own[i] == name) {
        return settle(ValueTarget.TypeParamOf(TypeTarget.GenericOf(def, i)))
    }
    let members = membersNamed(db, def, name)
    if (!members.isEmpty()) {
        let nonFuncs = members.iterator().any {member => !isFuncMember(db, member)}
        if (funcs.isEmpty() && nonFuncs) {
            return BodyResolution.Values(members.map {member => ValueTarget.MemberOf(member)})
        }
        for (member in members where isFuncMember(db, member)) {
            funcs.add(ValueTarget.MemberOf(member))
        }
        if (nonFuncs) {
            return BodyResolution.Values(funcs.toArray())
        }
    }
    if (let Some(parent) <- parentOf(db, def)) {
        let generics = signature(db, parent).generics
        for (i in 0..generics.size where generics[i] == name) {
            return settle(ValueTarget.TypeParamOf(TypeTarget.GenericOf(parent, i)))
        }
    }
    let inFile = lookUp(db, pkg, file, name, Namespace.Values)
    if (funcs.isEmpty()) {
        return BodyResolution.InFile(inFile)
    }
    // the file's functions join those found; anything else there (a variable, an ambiguity, nothing)
    // stops them, as a variable of a nearer level does (N63)
    if (let Found(ids) <- inFile && ids.iterator().all {id => id.item(db).kind == ItemKind.Func}) {
        for (id in ids) {
            funcs.add(ValueTarget.DeclOf(id))
        }
    }
    BodyResolution.Values(funcs.toArray())
}

/**
 * What each segment of `path`, a path of the type `ty` of the body of `def`, names: a type
 * parameter of a function the body declares around it, the innermost first (N68), else as in the
 * signature of `def` (`resolveTypePath`).
 */
public func resolveBodyTypePath(db: AnalysisDatabase, def: DefId, ty: TypeRefId, path: Array<String>): Array<PathResolution> {
    let scope = typeScopeOf(db, def) ?? return path.map {_ => PathResolution.UnresolvedPath}
    if (path.size == 1) {
        let scopes = exprScopes(db, def)
        for (one in scopes.chain(scopes.scopeOfType(ty))) {
            let data = scopes[one]
            if (let Some(index) <- data.genericsOf) {
                for (i in 0..data.generics.size where data.generics[i] == path[0]) {
                    return [PathResolution.Resolved(TypeTarget.LocalGenericOf(def, index, i))]
                }
            }
        }
    }
    resolveTypePath(db, scope, path)
}
