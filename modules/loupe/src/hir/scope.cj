package loupe.hir

import std.collection.*
import std.deriving.*
import calca.*
import calca.macros.*
import index_map.IndexMap
import loupe.db.{AnalysisDatabase, Package, SourceFile}

/**
 * The path of an import a name came by: its file, its import, the path's index in it, and the
 * visibility it re-exports with.
 */
@Derive[Equatable]
public struct ImportSite {
    public ImportSite(
        public let file: ItemFile,
        public let item: ItemId,
        public let path: Int64,
        public let level: Visibility
    ) {}
}

/**
 * What a name of a scope stands for: a declaration, or a package imported by its name (N7, N43).
 */
@Derive[Equatable, Hashable]
public enum ScopeTarget <: ToString {
    | OfDecl(DefId)
    | OfPackage(PackageRef)

    public func toString(): String {
        match (this) {
            case OfDecl(id) => id.toString()
            case OfPackage(pkg) => pkg.toString()
        }
    }
}

/**
 * A name an import brings, and the path it came by; `None` for the prelude.
 */
@Derive[Equatable]
public struct Imported {
    public Imported(public let target: ScopeTarget, public let site: ?ImportSite) {}
}

/**
 * An import of every name of a package, kept as the package: its names are read at a lookup.
 */
@Derive[Equatable]
public struct Glob {
    public Glob(
        public let pkg: PackageRef,
        /**
         * How the importer stands to it, for what it sees (N2–N4).
         */
        public let relation: PackageRelation,
        public let level: Visibility,
        public let site: ?ImportSite
    ) {}
}

/**
 * What imports bring, their names not read yet for a glob: the names of their paths, the
 * constructors of the enums among them (N44), and their globs.
 */
@Derive[Equatable]
public struct ImportedNames {
    public ImportedNames(
        public let names: IndexMap<String, Array<Imported>>,
        public let ctors: IndexMap<String, Array<DefId>>,
        public let globs: Array<Glob>
    ) {}
}

/**
 * The `ImportedNames` of `imports`, each with its file, made in the package `from`; `prelude`
 * after the globs of their own.
 */
func collectImports(db: AnalysisDatabase, from: PackageRef, imports: Array<(ItemFile, ImportItem)>, prelude: ?Glob): ImportedNames {
    let names = IndexMap<String, ArrayList<Imported>>()
    let ctors = IndexMap<String, ArrayList<DefId>>()
    let globs = ArrayList<Glob>()
    let fromName = nameOf(db, from)
    for ((file, item) in imports) {
        let level = importLevelOf(item)
        for (i in 0..item.paths.size) {
            let site = ImportSite(file, item.id, i, level)
            match (targetOf(db, from, item.paths[i], level)) {
                case PackageOf(name, pkg) => entryOf(names, name).add(Imported(ScopeTarget.OfPackage(pkg), site))
                case GlobOf(pkg, full) => globs.add(Glob(pkg, relationOf(fromName, full), level, site))
                case NameOf(pkg, pkgName, name, alias) =>
                    if (let ToNames(_, brought) <- namesOf(db, from, pkg, pkgName, level, (name, alias))) {
                        for ((each, ids) in brought) {
                            let entry = entryOf(names, each)
                            for (id in ids) {
                                entry.add(Imported(ScopeTarget.OfDecl(id), site))
                                for ((ctorName, ctor) in ctorsOf(db, id)) {
                                    entryOf(ctors, ctorName).add(ctor)
                                }
                            }
                        }
                    }
                case NoTarget(_) => ()
            }
        }
    }
    if (let Some(glob) <- prelude) {
        globs.add(glob)
    }
    ImportedNames(frozen(names) {list => list.toArray()}, frozen(ctors) {list => list.toArray()}, globs.toArray())
}

/**
 * What `pkg` re-exports (`internal import`, `public import`): seen in each of its files (N11), and
 * by its importers through its exports.
 */
@CalcaTracked[cycleResult: importsOnCycle]
public func packageImports(db: AnalysisDatabase, pkg: PackageRef): ImportedNames {
    let imports = ArrayList<(ItemFile, ImportItem)>()
    for (file in filesOf(db, pkg)) {
        for (item in itemTreeOf(db, file).imports where importLevelOf(item) != Visibility.Private) {
            imports.add((file, item))
        }
    }
    collectImports(db, pkg, imports.toArray(), None)
}

/**
 * Re-exports met again on a cycle of them: none; the exports on the cycle tell it.
 */
func importsOnCycle(_: AnalysisDatabase, _: PackageRef): ImportedNames {
    ImportedNames(IndexMap<String, Array<Imported>>(), IndexMap<String, Array<DefId>>(), [])
}

/**
 * The prelude of `pkg`: every name of `std.core`, an import of each file but of a package
 * compiled with `--no-prelude` (N39). `None` without a `std.core`.
 */
public func preludeOf(db: AnalysisDatabase, pkg: Package): ?Glob {
    if (pkg.noPrelude(db)) {
        return None
    }
    let from = PackageRef.Source(pkg)
    let core = packageIndex(db).find("std.core", from: from) ?? return None
    if (core == from) {
        return None
    }
    Glob(core, relationOf(pkg.name(db), "std.core"), Visibility.Private, None)
}

/**
 * What the plain imports of `file`, of `pkg`, bring, the prelude among its globs; the package's
 * re-exports are `packageImports`'s. A glob is its package: what it brings is read at a lookup,
 * so a name added to a package leaves this alone.
 */
@CalcaTracked
public func fileImports(db: AnalysisDatabase, pkg: Package, file: SourceFile): ImportedNames {
    let own = ItemFile.Source(file)
    let imports = itemTree(db, file).imports.filter {item => importLevelOf(item) == Visibility.Private}.map {
        item => (own, item)
    }
    collectImports(db, PackageRef.Source(pkg), imports, preludeOf(db, pkg))
}

/**
 * The level of imports of a file's scope (N11, N39): its plain imports, its package's re-exports
 * and the prelude, one level, none shadowing another. A glob is read by name at each lookup, not
 * copied whole into each file (D47).
 */
public struct ImportLevel {
    public ImportLevel(public let file: ImportedNames, public let pkg: ImportedNames) {}

    /**
     * Everything the level has by `name`, a declaration as often as it is brought.
     */
    public func names(db: AnalysisDatabase, name: String): Array<Imported> {
        let found = ArrayList<Imported>()
        found.add(all: file.names.get(name) ?? [])
        found.add(all: pkg.names.get(name) ?? [])
        for (glob in file.globs.iterator().concat(pkg.globs.iterator())) {
            let exports = packageExports(db, glob.pkg)
            for (id in visibleOf(exports.names.get(name) ?? [], glob.relation, glob.level)) {
                found.add(Imported(ScopeTarget.OfDecl(id), glob.site))
            }
        }
        found.toArray()
    }

    /**
     * The constructors of the enums it has, by `name`.
     */
    public func ctors(db: AnalysisDatabase, name: String): Array<DefId> {
        let found = ArrayList<DefId>()
        found.add(all: file.ctors.get(name) ?? [])
        found.add(all: pkg.ctors.get(name) ?? [])
        for (glob in file.globs.iterator().concat(pkg.globs.iterator())) {
            let exports = packageExports(db, glob.pkg)
            found.add(all: visibleOf(exports.ctors.get(name) ?? [], glob.relation, glob.level))
        }
        found.toArray()
    }
}

/**
 * The level of imports of `file`, of `pkg`.
 */
public func importsOf(db: AnalysisDatabase, pkg: Package, file: SourceFile): ImportLevel {
    ImportLevel(fileImports(db, pkg, file), packageImports(db, PackageRef.Source(pkg)))
}

/**
 * Where a name is used: as a type, or as a value (N41). A type does not see functions or
 * variables; neither sees a macro.
 */
@Derive[Equatable]
public enum Namespace {
    | Types
    | Values
}

/**
 * What a name means in a file's scope.
 */
@Derive[Equatable]
public enum Resolution <: ToString {
    /**
     * One declaration, or functions overloading one another (N5, N14, N42).
     */
    | Found(Array<DefId>)
    /**
     * A package imported by its name (N7, N8).
     */
    | FoundPackage(PackageRef)
    /**
     * Several things of one level, not all functions: an error at the use (N15, N16, N39).
     */
    | Ambiguous(Array<ScopeTarget>)
    /**
     * Constructors: the package's own, then those of imported enums; the expected type chooses
     * among all, the own ones without one (N46).
     */
    | Ctors(Array<DefId>, Array<DefId>)
    | NotFound

    public func toString(): String {
        match (this) {
            case Found(ids) => "found ${ids}"
            case FoundPackage(pkg) => "package ${pkg}"
            case Ambiguous(targets) => "ambiguous ${targets}"
            case Ctors(own, imported) => "ctors ${own} ${imported}"
            case NotFound => "not found"
        }
    }
}

/**
 * Whether a declaration of `kind` is seen in `ns`.
 */
func isIn(kind: ItemKind, ns: Namespace): Bool {
    match (kind) {
        case Macro => false
        case Class | Interface | Struct | Enum | TypeAlias | BuiltIn => true
        case _ => ns == Namespace.Values
    }
}

/**
 * Whether `target` is seen in `ns`: a package as a value, the first segment of a path (N43); as a
 * type it is none (N53), and the qualifier of a path in a type is looked up apart (N52).
 */
func isIn(target: ScopeTarget, db: AnalysisDatabase, ns: Namespace): Bool {
    match (target) {
        case OfDecl(id) => isIn(id.item(db).kind, ns)
        case OfPackage(_) => ns == Namespace.Values
    }
}

func isFunc(target: ScopeTarget, db: AnalysisDatabase): Bool {
    match (target) {
        case OfDecl(id) => id.item(db).kind == ItemKind.Func
        case OfPackage(_) => false
    }
}

/**
 * The constructors the imports of every file of a package bring, each seen in all of its files
 * (N73): those of the enums their paths name, and their globs, each glob once however many files
 * have it (the prelude is every file's).
 */
@Derive[Equatable]
public struct CtorImports {
    public CtorImports(public let ctors: IndexMap<String, Array<DefId>>, public let globs: Array<Glob>) {}

    /**
     * The constructors named `name`, each once.
     */
    public func named(db: AnalysisDatabase, name: String): Array<DefId> {
        let found = ArrayList<DefId>(ctors.get(name) ?? [])
        for (glob in globs) {
            for (id in visibleOf(packageExports(db, glob.pkg).ctors.get(name) ?? [], glob.relation, glob.level)
                where !found.contains(id)) {
                found.add(id)
            }
        }
        found.toArray()
    }
}

/**
 * The `CtorImports` of `pkg`: of its files' plain imports and of its re-exports.
 */
@CalcaTracked
public func packageCtorImports(db: AnalysisDatabase, pkg: Package): CtorImports {
    let ctors = IndexMap<String, ArrayList<DefId>>()
    let globs = ArrayList<Glob>()
    let levels = (pkg.files(db) |> filterMap {fileId => db.sourceFile(fileId)} |> map {file => fileImports(db, pkg, file)} |>
        collectArray).concat([packageImports(db, PackageRef.Source(pkg))])
    for (names in levels) {
        for ((name, ids) in names.ctors) {
            let entry = entryOf(ctors, name)
            for (id in ids where !entry.contains(id)) {
                entry.add(id)
            }
        }
        for (glob in names.globs where !globs.iterator().any {
            one => one.pkg == glob.pkg && one.relation == glob.relation && one.level == glob.level
        }) {
            globs.add(Glob(glob.pkg, glob.relation, glob.level, None))
        }
    }
    CtorImports(frozen(ctors) {list => list.toArray()}, globs.toArray())
}

/**
 * What `name`, used in `ns`, means in the file `from` of the package of `defs`, its imports
 * `imports`, those of every file of the package `ctorImports`. The levels, the first that has it
 * deciding: the package's declarations (N13, N40, N49), the imports (N39, N42, N43), the
 * constructors (N45, N46), of the enums any file of the package imports (N73). Functions gather
 * over the first two (N14).
 */
public func lookUpIn(db: AnalysisDatabase, defs: DefMap, from: ItemFile, imports: ImportLevel, name: String,
    ns: Namespace, ctorImports!: CtorImports): Resolution {
    let own = (defs.names.get(name) ?? []).filter {
        def => (def.visibility != Visibility.Private || def.id.file(db) == from) && isIn(def.id.item(db).kind, ns)
    }.map {def => def.id}
    let imported = ArrayList<ScopeTarget>()
    for (one in imports.names(db, name) where isIn(one.target, db, ns) && !imported.contains(one.target)) {
        imported.add(one.target)
    }
    if (!own.isEmpty()) {
        if (!own.iterator().all {id => id.item(db).kind == ItemKind.Func}) {
            return Resolution.Found(own)
        }
        let funcs = ArrayList<DefId>(own)
        for (target in imported) {
            if (let OfDecl(id) <- target && id.item(db).kind == ItemKind.Func && !funcs.contains(id)) {
                funcs.add(id)
            }
        }
        return Resolution.Found(funcs.toArray())
    }
    if (imported.size == 1) {
        return match (imported[0]) {
            case OfDecl(id) => Resolution.Found([id])
            case OfPackage(pkg) => Resolution.FoundPackage(pkg)
        }
    }
    if (imported.size > 1) {
        if (imported.iterator().all {target => isFunc(target, db)}) {
            return Resolution.Found(imported.toArray().map {target => match (target) {
                case OfDecl(id) => id
                case OfPackage(_) => throw IllegalStateException("a package among functions")
            }})
        }
        return Resolution.Ambiguous(imported.toArray())
    }
    if (ns == Namespace.Types) {
        return Resolution.NotFound
    }
    let ownCtors = (defs.ctors.get(name) ?? []).filter {
        def => def.visibility != Visibility.Private || def.id.file(db) == from
    }.map {def => def.id}
    let ctorsOfImports = ctorImports.named(db, name)
    if (ownCtors.isEmpty() && ctorsOfImports.isEmpty()) {
        Resolution.NotFound
    } else {
        Resolution.Ctors(ownCtors, ctorsOfImports)
    }
}

/**
 * What `name`, used in `ns`, means in `file` of `pkg`.
 */
public func lookUp(db: AnalysisDatabase, pkg: Package, file: SourceFile, name: String, ns: Namespace): Resolution {
    lookUpIn(db, defMap(db, PackageRef.Source(pkg)), ItemFile.Source(file), importsOf(db, pkg, file), name, ns,
        ctorImports: packageCtorImports(db, pkg))
}
