package loupe.hir

import std.collection.*
import std.deriving.*
import calca.*
import calca.macros.*
import loupe.db.{AnalysisDatabase, Package, SourceFile}

/**
 * What a segment of a path in a type names.
 */
@Derive[Equatable]
public enum TypeTarget <: ToString {
    /**
     * A type: a class, interface, struct, enum, alias, or a type of the compiler's own.
     */
    | TypeOf(DefId)
    /**
     * A type parameter: the declaration it is of, and its place among them.
     */
    | GenericOf(DefId, Int64)
    /**
     * A type parameter of a function declared in a body (N68): the declaration of the body, the
     * function's place among its `funcs`, and the parameter's among the function's.
     */
    | LocalGenericOf(DefId, Int64, Int64)
    /**
     * A package imported by its name, before the type it holds (N51).
     */
    | QualifierOf(PackageRef)

    public func toString(): String {
        match (this) {
            case TypeOf(id) => "type ${id}"
            case GenericOf(id, index) => "generic ${index} of ${id}"
            case LocalGenericOf(id, local, index) => "generic ${index} of local ${local} of ${id}"
            case QualifierOf(pkg) => "package ${pkg}"
        }
    }
}

/**
 * What a segment of a path in a type resolves to.
 */
@Derive[Equatable]
public enum PathResolution <: ToString {
    | Resolved(TypeTarget)
    /**
     * Types of one level of the file's scope, or of a package's exports (N15, N33, N39).
     */
    | AmbiguousPath(Array<ScopeTarget>)
    /**
     * Packages imported by one name, as a qualifier (N52).
     */
    | ConflictedPackages(Array<PackageRef>)
    /**
     * Nothing, or no type: a function, a package or a constructor where a type stands (N53, N54),
     * a segment after a type (N54) or after one not resolved.
     */
    | UnresolvedPath

    public func toString(): String {
        match (this) {
            case Resolved(target) => target.toString()
            case AmbiguousPath(targets) => "ambiguous ${targets}"
            case ConflictedPackages(pkgs) => "conflicted ${pkgs}"
            case UnresolvedPath => "unresolved"
        }
    }
}

/**
 * The type parameters of one declaration: the declaration, which `GenericOf` names, and their
 * names in order, an index among them a `GenericOf`'s.
 */
public struct Generics {
    public Generics(public let owner: DefId, public let names: Array<String>) {}
}

/**
 * Where the types of a declaration's signature are looked up, rust-analyzer's `Resolver`: the type
 * parameters of the declaration, then of the type or `extend` it is a member of, the innermost
 * first, each shadowing anything of its name (N55); then the scope of its file.
 */
public struct TypeScope {
    public TypeScope(
        /**
         * The type parameters of the declaration, then of its parent, if it has one.
         */
        public let generics: Array<Generics>,
        public let pkg: Package,
        public let file: SourceFile
    ) {}
}

/**
 * The `TypeScope` of `def`; `None` for a declaration of a package compiled already, or of a file of
 * no package.
 */
public func typeScopeOf(db: AnalysisDatabase, def: DefId): ?TypeScope {
    let file = scopeFileOf(db, def.file(db)) ?? return None
    let pkg = packageOfFile(db, file) ?? return None
    let generics = ArrayList<Generics>([Generics(def, signature(db, def).generics)])
    if (let Some(parent) <- parentOf(db, def)) {
        generics.add(Generics(parent, signature(db, parent).generics))
    }
    TypeScope(generics.toArray(), pkg, file)
}

/**
 * The type or `extend` `def` is a member of, an enum its constructor's. A query: what reads it, a
 * name of a body resolved or highlighted, asks it of every name, and the search is over the file.
 */
@CalcaTracked
public func parentOf(db: AnalysisDatabase, def: DefId): ?DefId {
    let file = def.file(db)
    let id = def.item(db)
    for (item in itemTreeOf(db, file).items where item.members.iterator().any {member => member.id == id}) {
        return DefId(db, file, item.id)
    }
    None
}

/**
 * The package of the project `file` is in.
 */
@CalcaTracked
public func packageOfFile(db: AnalysisDatabase, file: SourceFile): ?Package {
    let project = db.project() ?? return None
    let fileId = file.fileId(db)
    for (module in project.modules(db)) {
        for (pkg in module.packages(db) where pkg.files(db).contains(fileId)) {
            return pkg
        }
    }
    None
}

/**
 * What each segment of `path`, a path in a type, names in `scope`. A first segment followed by
 * others is a package imported by its name, if one is (N51, N52), even where a declaration or a
 * type parameter has the name; else it is a type, as a path of one segment is. After a package
 * comes one of its types; nothing comes after a type (N54).
 */
public func resolveTypePath(db: AnalysisDatabase, scope: TypeScope, path: Array<String>): Array<PathResolution> {
    if (path.isEmpty()) {
        return []
    }
    let first = if (path.size > 1) {
        qualifierNamed(db, scope, path[0])
    } else {
        None<PathResolution>
    }
    let found = ArrayList<PathResolution>([first ?? typeNamed(db, scope, path[0])])
    var pkg = match (found[0]) {
        case Resolved(QualifierOf(one)) => Some(one)
        case _ => None<PackageRef>
    }
    for (i in 1..path.size) {
        match (pkg) {
            case Some(one) => found.add(typeOfPackage(db, scope, one, path[i]))
            case None => found.add(PathResolution.UnresolvedPath)
        }
        pkg = None
    }
    found.toArray()
}

/**
 * The package the file imports by `name`, as the qualifier of a path (N51, N52): of its imports
 * alone, whatever else has the name.
 */
func qualifierNamed(db: AnalysisDatabase, scope: TypeScope, name: String): ?PathResolution {
    let pkgs = ArrayList<PackageRef>()
    for (one in importsOf(db, scope.pkg, scope.file).names(db, name)) {
        if (let OfPackage(pkg) <- one.target && !pkgs.contains(pkg)) {
            pkgs.add(pkg)
        }
    }
    match (pkgs.size) {
        case 0 => None<PathResolution>
        case 1 => PathResolution.Resolved(QualifierOf(pkgs[0]))
        case _ => PathResolution.ConflictedPackages(pkgs.toArray())
    }
}

/**
 * The type `name` names in `scope`: a type parameter, else a type of the file's scope.
 */
func typeNamed(db: AnalysisDatabase, scope: TypeScope, name: String): PathResolution {
    for (generics in scope.generics) {
        for (i in 0..generics.names.size where generics.names[i] == name) {
            return PathResolution.Resolved(GenericOf(generics.owner, i))
        }
    }
    match (lookUp(db, scope.pkg, scope.file, name, Namespace.Types)) {
        // more than one only for a type redefined in its package (N19): the first stands
        case Found(ids) => PathResolution.Resolved(TypeOf(ids[0]))
        case Ambiguous(targets) => PathResolution.AmbiguousPath(targets)
        case _ => PathResolution.UnresolvedPath
    }
}

/**
 * The type `name` names among the exports of `pkg` that `scope`'s package sees.
 */
func typeOfPackage(db: AnalysisDatabase, scope: TypeScope, pkg: PackageRef, name: String): PathResolution {
    let relation = relationOf(scope.pkg.name(db), nameOf(db, pkg))
    let ids = visibleOf(packageExports(db, pkg).names.get(name) ?? [], relation, Visibility.Private).filter {
        id => isIn(id.item(db).kind, Namespace.Types)
    }
    match (ids.size) {
        case 0 => PathResolution.UnresolvedPath
        case 1 => PathResolution.Resolved(TypeOf(ids[0]))
        case _ => PathResolution.AmbiguousPath(ids.map {id => ScopeTarget.OfDecl(id)})
    }
}
