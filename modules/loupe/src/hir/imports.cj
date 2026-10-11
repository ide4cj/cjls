package loupe.hir

import std.collection.*
import std.deriving.*
import calca.*
import calca.macros.*
import index_map.IndexMap
import loupe.db.AnalysisDatabase

/**
 * The full name of `pkg`, as its files declare it: `std.collection`, `org::a.b`.
 */
public func nameOf(db: AnalysisDatabase, pkg: PackageRef): String {
    match (pkg) {
        case Source(source) => source.name(db)
        case Binary(binary) => binary.name(db)
    }
}

/**
 * A package of the project and who it is of: a module's name, or a binary's.
 */
@Derive[Equatable]
public struct IndexedPackage {
    public IndexedPackage(public let pkg: PackageRef, public let owner: String) {}
}

/**
 * The packages of the project by name, for the imports to find (D46): those of its modules and of
 * its binaries, and what each module may import from.
 */
@Derive[Equatable]
public struct PackageIndex {
    public PackageIndex(
        public let packages: IndexMap<String, Array<IndexedPackage>>,
        /**
         * Who each package is of, a module or a binary.
         */
        public let owners: IndexMap<PackageRef, String>,
        /**
         * What each module may import from: itself, its deps, and `std`.
         */
        public let scopes: IndexMap<String, Array<String>>
    ) {}

    /**
     * The package `name` names in an import of `from`: one of its module, of a module or binary
     * among its deps, or of `std`; for a package compiled already, which found it once, one of its
     * binary first, else any.
     */
    public func find(name: String, from!: PackageRef): ?PackageRef {
        let candidates = packages.get(name) ?? return None
        let owner = owners.get(from) ?? ""
        match (from) {
            case Source(_) =>
                let scope = scopes.get(owner) ?? []
                candidates.iterator().filter {it => scope.contains(it.owner)}.next().map {it => it.pkg}
            case Binary(_) =>
                let own = candidates.iterator().filter {it => it.owner == owner}.next()
                (own ?? candidates[0]).pkg
        }
    }
}

/**
 * The `PackageIndex` of the project; empty while there is none. It changes only when packages come
 * or go, or a module's deps do.
 */
@CalcaTracked
public func packageIndex(db: AnalysisDatabase): PackageIndex {
    let packages = IndexMap<String, ArrayList<IndexedPackage>>()
    let owners = IndexMap<PackageRef, String>()
    let scopes = IndexMap<String, Array<String>>()
    if (let Some(project) <- db.project()) {
        for (module in project.modules(db)) {
            let owner = module.name(db)
            scopes[owner] = [owner].concat(module.deps(db)).concat(["std"])
            for (pkg in module.packages(db)) {
                let ref = PackageRef.Source(pkg)
                entryOf(packages, pkg.name(db)).add(IndexedPackage(ref, owner))
                owners[ref] = owner
            }
        }
        for (binary in project.binaryPackages(db)) {
            let ref = PackageRef.Binary(binary)
            entryOf(packages, binary.name(db)).add(IndexedPackage(ref, binary.binary(db)))
            owners[ref] = binary.binary(db)
        }
    }
    PackageIndex(frozen(packages) {list => list.toArray()}, owners, scopes)
}

/**
 * How a package that refers to a declaration stands to the package declaring it, cjc's
 * `PackageRelation`: the same, one under it by name (`m.a.b` to `m.a`), one of the same first
 * segment (cjc's module), or none of these.
 */
@Derive[Equatable]
public enum PackageRelation {
    | SamePackage
    | Child
    | SameModule
    | Unrelated
}

/**
 * How `from` stands to `target`, both full names: `org::a` is one segment.
 */
public func relationOf(from: String, target: String): PackageRelation {
    if (from == target) {
        return PackageRelation.SamePackage
    }
    let src = from.split(".")
    let dst = target.split(".")
    if (dst.size < src.size && dst.iterator().zip(src.iterator()).all {pair => pair[0] == pair[1]}) {
        PackageRelation.Child
    } else if (src[0] == dst[0]) {
        PackageRelation.SameModule
    } else {
        PackageRelation.Unrelated
    }
}

extend Visibility {
    /**
     * Whether a declaration of this visibility is seen by a package standing so to its own (N1–N4).
     */
    public func isSeen(by!: PackageRelation): Bool {
        match ((this, by)) {
            case (Public, _) | (_, SamePackage) => true
            case (Protected, rel) => rel != PackageRelation.Unrelated
            case (Internal, rel) => rel == PackageRelation.Child
            case _ => false
        }
    }

    /**
     * Its place among the four, `private` the narrowest: cjc's `AccessLevel`.
     */
    public prop rank: Int64 {
        get() {
            match (this) {
                case Private => 0
                case Internal => 1
                case Protected => 2
                case Public => 3
            }
        }
    }
}

/**
 * The visibility `item` re-exports with: `private`, re-exporting nothing, unless written.
 */
public func importLevelOf(item: ImportItem): Visibility {
    if (item.modifiers.contains(Modifier.Public)) {
        Visibility.Public
    } else if (item.modifiers.contains(Modifier.Protected)) {
        Visibility.Protected
    } else if (item.modifiers.contains(Modifier.Internal)) {
        Visibility.Internal
    } else {
        Visibility.Private
    }
}

/**
 * Why a path of an import brings nothing, as cjpm and cjc report it.
 */
@Derive[Equatable]
public enum ImportError <: ToString {
    /**
     * No package of the name the importer may import (cjpm's "can not find the following dependencies").
     */
    | NoPackage(String)
    /**
     * The package has no declaration of the name its importer sees (N35), an enum's constructor
     * included (N38).
     */
    | NotAccessible(String, String)
    /**
     * A package re-exported (N31).
     */
    | PackageReExported(String)
    /**
     * A package reached again through its re-exports (N36).
     */
    | Cycle(String)
    /**
     * A package importing itself (N47).
     */
    | SelfImport(String)

    public func toString(): String {
        match (this) {
            case NoPackage(name) => "can not find package '${name}'"
            case NotAccessible(name, pkg) => "'${name}' is not accessible in package '${pkg}'"
            case PackageReExported(name) => "imported package name '${name}' cannot be re-exported"
            case Cycle(name) => "cyclic dependency through '${name}'"
            case SelfImport(name) => "package '${name}' should not import itself"
        }
    }
}

/**
 * What a path of an import brings into a scope.
 */
public enum ImportResolution {
    /**
     * A package, under the name its path ends in or its alias (N7, N8): `a.C` then.
     */
    | ToPackage(String, PackageRef)
    /**
     * Declarations of a package by name: one name for `p.f` or `p.C as D` (N5, N6), every name the
     * importer sees for `p.*` (N10).
     */
    | ToNames(PackageRef, IndexMap<String, Array<DefId>>)
    | Unresolved(ImportError)
}


/**
 * What a path of an import names, before the names it brings are read: a package, every name of
 * one, or one name of one.
 */
public enum ImportTarget {
    /**
     * A package, under the name its path ends in or its alias (N7, N8).
     */
    | PackageOf(String, PackageRef)
    /**
     * Every name of a package (`p.*`), the package and its full name.
     */
    | GlobOf(PackageRef, String)
    /**
     * One name of a package (`p.f`, `p.C as D`): the package, its full name, the name, its alias.
     */
    | NameOf(PackageRef, String, String, ?String)
    | NoTarget(ImportError)
}

/**
 * A package importing itself, an error at the path (N47): `name` is the path as written.
 */
func selfImport(from: PackageRef, target: PackageRef, name: String): ?ImportTarget {
    if (target == from) {
        ImportTarget.NoTarget(ImportError.SelfImport(name))
    } else {
        None
    }
}

/**
 * What `path`, of an import `level` re-exports with, names from `from`. A path naming a package is
 * the package (N30); else its last segment is a name of the package the others name. A package
 * importing itself names nothing (N47).
 */
public func targetOf(db: AnalysisDatabase, from: PackageRef, path: ImportPath, level: Visibility): ImportTarget {
    let index = packageIndex(db)
    let full = String.join(path.segments, delimiter: ".")
    if (path.isGlob) {
        let target = index.find(full, from: from) ?? return ImportTarget.NoTarget(ImportError.NoPackage(full))
        return selfImport(from, target, full) ?? ImportTarget.GlobOf(target, full)
    }
    if (let Some(target) <- index.find(full, from: from)) {
        if (let Some(error) <- selfImport(from, target, full)) {
            return error
        }
        if (level != Visibility.Private) {
            return ImportTarget.NoTarget(ImportError.PackageReExported(full))
        }
        return ImportTarget.PackageOf(path.alias ?? path.segments[path.segments.size - 1], target)
    }
    if (path.segments.size < 2) {
        return ImportTarget.NoTarget(ImportError.NoPackage(full))
    }
    let pkgName = String.join(path.segments[..path.segments.size - 1], delimiter: ".")
    let target = index.find(pkgName, from: from) ?? return ImportTarget.NoTarget(ImportError.NoPackage(pkgName))
    selfImport(from, target, pkgName) ?? ImportTarget.NameOf(target, pkgName, path.segments[path.segments.size - 1], path.alias)
}

/**
 * What `path`, of an import `level` re-exports with, brings into `from`: its target (`targetOf`)
 * and, for names, those of the package's exports `from` sees (N2–N4), those of a visibility
 * narrower than `level` left out (N37).
 */
public func resolveImport(db: AnalysisDatabase, from: PackageRef, path: ImportPath, level: Visibility): ImportResolution {
    match (targetOf(db, from, path, level)) {
        case PackageOf(name, target) => ImportResolution.ToPackage(name, target)
        case GlobOf(target, full) => namesOf(db, from, target, full, level, None)
        case NameOf(target, pkgName, name, alias) => namesOf(db, from, target, pkgName, level, (name, alias))
        case NoTarget(error) => ImportResolution.Unresolved(error)
    }
}

/**
 * The declarations of `defs` a package standing so to theirs sees, and an import of `level` keeps:
 * one too narrow for it is left out silently, as cjc does (N37).
 */
public func visibleOf(defs: Array<Def>, relation: PackageRelation, level: Visibility): Array<DefId> {
    defs.filter {def => def.visibility.isSeen(by: relation) && level.rank <= def.visibility.rank}.map {def => def.id}
}

/**
 * The exports of `target`, named `targetName`, seen by `from` and no narrower than `level`: all of
 * them, or the one `name` under its alias.
 */
func namesOf(db: AnalysisDatabase, from: PackageRef, target: PackageRef, targetName: String, level: Visibility,
    name: ?(String, ?String), stage!: ScopeStage = ScopeStage.Expanded): ImportResolution {
    let exports = exportsAt(db, target, stage)
    if (exports.cyclic) {
        return ImportResolution.Unresolved(ImportError.Cycle(targetName))
    }
    let relation = relationOf(nameOf(db, from), targetName)
    let names = IndexMap<String, Array<DefId>>()
    match (name) {
        case Some((one, alias)) =>
            let defs = exports.names.get(one) ?? []
            if (!defs.iterator().any {def => def.visibility.isSeen(by: relation)}) {
                return ImportResolution.Unresolved(ImportError.NotAccessible(one, targetName))
            }
            names[alias ?? one] = visibleOf(defs, relation, level)
        case None => for ((each, defs) in exports.names) {
            let ids = visibleOf(defs, relation, level)
            if (!ids.isEmpty()) {
                names[each] = ids
            }
        }
    }
    ImportResolution.ToNames(target, names)
}

/**
 * What a package shows to its importers (D46): its declarations but the `private` ones, and what
 * it re-exports, each with the visibility of its import (N11, N28, N29, N32), one name a set of
 * both and no shadowing between them (N33), a declaration once (N34). Under them, the constructors
 * of the enums among them by name, which come with their enum (N44). `cyclic` when its re-exports
 * reach it again (N36): nothing then.
 */
@Derive[Equatable]
public struct PackageExports {
    public PackageExports(
        public let names: IndexMap<String, Array<Def>>,
        public let ctors!: IndexMap<String, Array<Def>> = IndexMap<String, Array<Def>>(),
        public let cyclic!: Bool = false
    ) {}
}

/**
 * The `PackageExports` of `pkg`, what the macros called in it add included: `exportsAt` `Expanded`.
 */
public func packageExports(db: AnalysisDatabase, pkg: PackageRef): PackageExports {
    exportsAt(db, pkg, ScopeStage.Expanded)
}

/**
 * The `PackageExports` of `pkg` at `stage`, on those of the packages it re-exports from: a chain
 * of queries down the packages, no fixed point (D44), for an import names a package by its full
 * name and packages import one another in no cycle.
 */
@CalcaTracked[cycleResult: exportsOnCycle]
public func exportsAt(db: AnalysisDatabase, pkg: PackageRef, stage: ScopeStage): PackageExports {
    if (let Binary(_) <- pkg && stage == ScopeStage.Written) {
        return exportsAt(db, pkg, ScopeStage.Expanded)
    }
    let names = IndexMap<String, ArrayList<Def>>()
    for ((name, defs) in defMapAt(db, pkg, stage).names) {
        for (def in defs where def.visibility != Visibility.Private) {
            addOnce(entryOf(names, name), def)
        }
    }
    let reExported = packageImportsAt(db, pkg, stage)
    for ((name, imported) in reExported.names) {
        let entry = entryOf(names, name)
        for (one in imported) {
            if (let (OfDecl(id), Some(site)) <- (one.target, one.site)) {
                addOnce(entry, Def(id, site.level))
            }
        }
    }
    for (glob in reExported.globs) {
        let exports = exportsAt(db, glob.pkg, stage)
        for ((name, defs) in exports.names) {
            let ids = visibleOf(defs, glob.relation, glob.level)
            if (!ids.isEmpty()) {
                let entry = entryOf(names, name)
                for (id in ids) {
                    addOnce(entry, Def(id, glob.level))
                }
            }
        }
    }
    let ctors = IndexMap<String, ArrayList<Def>>()
    for ((_, defs) in names) {
        for (def in defs) {
            for ((name, ctor) in ctorsOf(db, def.id)) {
                addOnce(entryOf(ctors, name), Def(ctor, def.visibility))
            }
        }
    }
    PackageExports(frozen(names) {defs => defs.toArray()}, ctors: frozen(ctors) {defs => defs.toArray()})
}

/**
 * Exports met again on a cycle of re-exports: none, and the cycle told.
 */
func exportsOnCycle(_: AnalysisDatabase, _: PackageRef, _: ScopeStage): PackageExports {
    PackageExports(IndexMap<String, Array<Def>>(), cyclic: true)
}

/**
 * Adds `def` to `defs` unless its declaration is there; there, the wider of the two visibilities.
 */
func addOnce(defs: ArrayList<Def>, def: Def): Unit {
    for (i in 0..defs.size where defs[i].id == def.id) {
        if (defs[i].visibility.rank < def.visibility.rank) {
            defs[i] = def
        }
        return
    }
    defs.add(def)
}

/**
 * The item `def` stands for, `None` once its file no longer has it.
 */
public func itemOf(db: AnalysisDatabase, def: DefId): ?Item {
    let id = def.item(db)
    itemTreeOf(db, def.file(db)).items.iterator().filter {item => item.id == id}.next()
}

/**
 * The constructors of `def` by name, if it is an enum: none else.
 */
public func ctorsOf(db: AnalysisDatabase, def: DefId): Array<(String, DefId)> {
    if (def.item(db).kind != ItemKind.Enum) {
        return []
    }
    let item = itemOf(db, def) ?? return []
    let file = def.file(db)
    let ctors = ArrayList<(String, DefId)>()
    for (ctor in item.members where ctor.kind == ItemKind.EnumCtor) {
        for (name in ctor.names) {
            ctors.add((name, DefId(db, file, ctor.id)))
        }
    }
    ctors.toArray()
}
