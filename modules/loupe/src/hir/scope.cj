package loupe.hir

import std.collection.*
import std.deriving.*
import calca.*
import calca.macros.*
import index_map.IndexMap
import loupe.db.{AnalysisDatabase, Package, SourceFile}
import loupe.vfs.FileId
import py_interop.*
import py_interop.internal_macros.DerivePython

/**
 * The path of an import a name came by: its file, its import, the path's index in it, and the
 * visibility it re-exports with.
 */
@DerivePython
public struct ImportSite <: Equatable<ImportSite> {
    public ImportSite(
        public let file: ItemFile,
        public let item: ItemId,
        public let path: Int64,
        public let level: Visibility
    ) {}

    public operator func ==(other: ImportSite): Bool {
        file == other.file && item == other.item && path == other.path && level == other.level
    }

    public operator func !=(other: ImportSite): Bool {
        !(this == other)
    }
}

/**
 * What a name of a scope stands for: a declaration, or a package imported by its name (N7, N43).
 */
@DerivePython
public enum ScopeTarget <: ToString & Equatable<ScopeTarget> & Hashable {
    | OfDecl(DefId)
    | OfPackage(PackageRef)

    public func toString(): String {
        match (this) {
            case OfDecl(id) => id.toString()
            case OfPackage(pkg) => pkg.toString()
        }
    }

    public operator func ==(other: ScopeTarget): Bool {
        match ((this, other)) {
            case (ScopeTarget.OfDecl(left0), ScopeTarget.OfDecl(right0)) => left0 == right0
            case (ScopeTarget.OfPackage(left0), ScopeTarget.OfPackage(right0)) => left0 == right0
            case _ => false
        }
    }

    public operator func !=(other: ScopeTarget): Bool {
        !(this == other)
    }

    public func hashCode(): Int64 {
        var hasher = DefaultHasher()
        match (this) {
            case ScopeTarget.OfDecl(value0) =>
                hasher.write(0)
                hasher.write(value0.hashCode())
            case ScopeTarget.OfPackage(value0) =>
                hasher.write(1)
                hasher.write(value0.hashCode())
        }
        hasher.finish()
    }
}

/**
 * A name an import brings, and the path it came by; `None` for the prelude.
 */
@DerivePython
public struct Imported <: Equatable<Imported> {
    public Imported(public let target: ScopeTarget, public let site: ?ImportSite) {}

    public operator func ==(other: Imported): Bool {
        target == other.target && site == other.site
    }

    public operator func !=(other: Imported): Bool {
        !(this == other)
    }
}

/**
 * An import of every name of a package, kept as the package: its names are read at a lookup.
 */
@DerivePython
public struct Glob <: Equatable<Glob> {
    public Glob(
        public let pkg: PackageRef,
        /**
         * How the importer stands to it, for what it sees (N2–N4).
         */
        public let relation: PackageRelation,
        public let level: Visibility,
        public let site: ?ImportSite
    ) {}

    public operator func ==(other: Glob): Bool {
        pkg == other.pkg && relation == other.relation && level == other.level && site == other.site
    }

    public operator func !=(other: Glob): Bool {
        !(this == other)
    }
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
 * The `ImportedNames` of `imports`, each with its file, made in the package `from`; `implicit`, the globs no line
 * writes (the prelude), after those of their own.
 */
func collectImports(
    db: AnalysisDatabase,
    from: PackageRef,
    imports: Array<(ItemFile, ImportItem)>,
    implicit: Array<Glob>,
    stage: ScopeStage
): ImportedNames {
    let names = IndexMap<String, ArrayList<Imported>>()
    let ctors = IndexMap<String, ArrayList<DefId>>()
    let globs = ArrayList<Glob>()
    let fromName = nameOf(db, from)
    for ((file, item) in imports) {
        let level = importLevelOf(item)
        for (i in 0..item.paths.size) {
            let site = ImportSite(file, item.id, i, level)
            match (targetOf(db, from, item.paths[i], level)) {
                case PackageOf(name, pkg) =>
                    entryOf(names, name).add(Imported(ScopeTarget.OfPackage(pkg), site))
                case GlobOf(pkg, full) =>
                    globs.add(Glob(pkg, relationOf(fromName, full), level, site))
                case NameOf(pkg, pkgName, name, alias) =>
                    if (
                        let ToNames(_, brought) <- namesOf(
                            db,
                            from,
                            pkg,
                            pkgName,
                            level,
                            (name, alias),
                            stage: stage
                        )
                    ) {
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
    globs.add(all: implicit)
    ImportedNames(
        frozen(names) { list => list.toArray() },
        frozen(ctors) { list => list.toArray() },
        globs.toArray()
    )
}

/**
 * What `pkg` re-exports (`internal import`, `public import`): seen in each of its files (N11), and
 * by its importers through its exports. `packageImportsAt` `Expanded`.
 */
public func packageImports(db: AnalysisDatabase, pkg: PackageRef): ImportedNames {
    packageImportsAt(db, pkg, ScopeStage.Expanded)
}

/**
 * What `pkg` re-exports, the names of the packages they name read at `stage`.
 */
@CalcaTracked[cycleResult: importsOnCycle]
public func packageImportsAt(
    db: AnalysisDatabase,
    pkg: PackageRef,
    stage: ScopeStage
): ImportedNames {
    let imports = ArrayList<(ItemFile, ImportItem)>()
    for (file in filesOf(db, pkg)) {
        for (item in itemTreeOf(db, file).imports where importLevelOf(item) != Visibility.Private) {
            imports.add((file, item))
        }
    }
    collectImports(db, pkg, imports.toArray(), [], stage)
}

/**
 * Re-exports met again on a cycle of them: none; the exports on the cycle tell it.
 */
func importsOnCycle(_: AnalysisDatabase, _: PackageRef, _: ScopeStage): ImportedNames {
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
    let from = resolutionPackage(db, pkg)
    let core = packageIndex(db).find("std.core", from: from) ?? return None
    if (core == from) {
        return None
    }
    Glob(core, relationOf(pkg.name(db), "std.core"), Visibility.Private, None)
}

/**
 * The packages a file compiled with `--test` imports with no line, as `cjc --test` does (`cjpm test`, D129):
 * std.unittest's names, its re-exports among them, and std.unittest.testmacro's macros.
 */
let TEST_IMPORTS = ["std.unittest", "std.unittest.testmacro"]

/**
 * What a test of `pkg`, `file` one of its `testFiles`, imports with no line: a glob of each of `TEST_IMPORTS` there
 * is (D129). None for any other file.
 */
public func testImportsOf(db: AnalysisDatabase, pkg: Package, file: SourceFile): Array<Glob> {
    if (!isTestOf(db, pkg, file)) {
        return []
    }
    let from = resolutionPackage(db, pkg)
    let name = pkg.name(db)
    TEST_IMPORTS |>
        filterMap {
            imported: String =>
            packageIndex(db)
                .find(imported, from: from)
                .flatMap {
                    found =>
                    if (found == from) {
                        None<Glob>
                    } else {
                        Glob(found, relationOf(name, imported), Visibility.Private, None)
                    }
                }
        } |>
        collectArray
}

/**
 * Whether `file` is one of the tests of `pkg`, which cjc compiles with the package only under `--test` (D129).
 */
public func isTestOf(db: AnalysisDatabase, pkg: Package, file: SourceFile): Bool {
    pkg.testFiles(db).contains(file.fileId(db))
}

/**
 * What the plain imports of `file`, of `pkg`, bring, the prelude among its globs, and std.unittest's in a test
 * (`testImportsOf`); the package's re-exports are `packageImports`'s. A glob is its package: what it brings is
 * read at a lookup, so a name added to a package leaves this alone. `fileImportsAt` `Expanded`.
 */
public func fileImports(db: AnalysisDatabase, pkg: Package, file: SourceFile): ImportedNames {
    fileImportsAt(db, pkg, file, ScopeStage.Expanded)
}

/**
 * What the plain imports of `file`, of `pkg`, bring, the names of the packages they name read at
 * `stage`.
 */
@CalcaTracked
public func fileImportsAt(
    db: AnalysisDatabase,
    pkg: Package,
    file: SourceFile,
    stage: ScopeStage
): ImportedNames {
    let own = ItemFile.Source(file)
    let imports =
        activeItemTree(db, file)
            .imports
            .filter { item => importLevelOf(item) == Visibility.Private }
            .map { item => (own, item) }
    let prelude = preludeOf(db, pkg).map { glob => [glob] } ?? []
    collectImports(
        db,
        resolutionPackage(db, pkg),
        imports,
        prelude.concat(testImportsOf(db, pkg, file)),
        stage
    )
}

/**
 * The level of imports of a file's scope (N11, N39): its plain imports, its package's re-exports
 * and the prelude, one level, none shadowing another. A glob is read by name at each lookup, not
 * copied whole into each file (D47).
 */
public struct ImportLevel {
    public ImportLevel(
        public let file: ImportedNames,
        public let pkg: ImportedNames,
        /**
         * What the packages of its globs are read at.
         */
        public let stage!: ScopeStage = ScopeStage.Expanded
    ) {}

    /**
     * Everything the level has by `name`, a declaration as often as it is brought.
     */
    public func names(db: AnalysisDatabase, name: String): Array<Imported> {
        let found = ArrayList<Imported>()
        found.add(all: file.names.get(name) ?? [])
        found.add(all: pkg.names.get(name) ?? [])
        for (glob in file.globs.iterator().concat(pkg.globs.iterator())) {
            let exports = exportsAt(db, glob.pkg, stage)
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
            let exports = exportsAt(db, glob.pkg, stage)
            found.add(all: visibleOf(exports.ctors.get(name) ?? [], glob.relation, glob.level))
        }
        found.toArray()
    }
}

/**
 * The level of imports of `file`, of `pkg`.
 */
public func importsOf(db: AnalysisDatabase, pkg: Package, file: SourceFile): ImportLevel {
    importsAt(db, pkg, file, ScopeStage.Expanded)
}

/**
 * The level of imports of `file`, of `pkg`, the packages it names read at `stage`.
 */
public func importsAt(
    db: AnalysisDatabase,
    pkg: Package,
    file: SourceFile,
    stage: ScopeStage
): ImportLevel {
    ImportLevel(
        fileImportsAt(db, pkg, file, stage),
        packageImportsAt(db, resolutionPackage(db, pkg), stage),
        stage: stage
    )
}

/**
 * Where a name is used: as a type, or as a value (N41), or as the macro of a call. A type does not
 * see functions or variables; neither sees a macro, nor a macro anything else (a function `Derive`
 * leaves `@Derive` the imported macro).
 */
@DerivePython
public enum Namespace <: Equatable<Namespace> & Hashable {
    | Types
    | Values
    | Macros

    public operator func ==(other: Namespace): Bool {
        match ((this, other)) {
            case (Namespace.Types, Namespace.Types) => true
            case (Namespace.Values, Namespace.Values) => true
            case (Namespace.Macros, Namespace.Macros) => true
            case _ => false
        }
    }

    public operator func !=(other: Namespace): Bool {
        !(this == other)
    }

    public func hashCode(): Int64 {
        var hasher = DefaultHasher()
        match (this) {
            case Namespace.Types => hasher.write(0)
            case Namespace.Values => hasher.write(1)
            case Namespace.Macros => hasher.write(2)
        }
        hasher.finish()
    }
}

/**
 * What a name means in a file's scope.
 */
@DerivePython
public enum Resolution <: ToString & Equatable<Resolution> {
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

    public operator func ==(other: Resolution): Bool {
        match ((this, other)) {
            case (Resolution.Found(left0), Resolution.Found(right0)) => left0 == right0
            case (Resolution.FoundPackage(left0), Resolution.FoundPackage(right0)) =>
                left0 == right0
            case (Resolution.Ambiguous(left0), Resolution.Ambiguous(right0)) => left0 == right0
            case (Resolution.Ctors(left0, left1), Resolution.Ctors(right0, right1)) =>
                left0 == right0 && left1 == right1
            case (Resolution.NotFound, Resolution.NotFound) => true
            case _ => false
        }
    }

    public operator func !=(other: Resolution): Bool {
        !(this == other)
    }
}

/**
 * Whether a declaration of `kind` is seen in `ns`.
 */
func isIn(kind: ItemKind, ns: Namespace): Bool {
    match (kind) {
        case Macro => ns == Namespace.Macros
        case Class | Interface | Struct | Enum | TypeAlias | BuiltIn => ns != Namespace.Macros
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
 * have it (the prelude is every file's). A file that is no test sees those of the files that are
 * none alone, as `cjpm build` compiles them (N164, D129).
 */
@Derive[Equatable]
public struct CtorImports {
    public CtorImports(
        public let ctors: IndexMap<String, Array<DefId>>,
        public let globs: Array<Glob>
    ) {}

    /**
     * The constructors named `name`, each once.
     */
    public func named(db: AnalysisDatabase, name: String): Array<DefId> {
        let found = ArrayList<DefId>(ctors.get(name) ?? [])
        for (glob in globs) {
            for (
                id in visibleOf(
                    packageExports(db, glob.pkg).ctors.get(name) ?? [],
                    glob.relation,
                    glob.level
                ) where !found.contains(id)
            ) {
                found.add(id)
            }
        }
        found.toArray()
    }
}

/**
 * The `CtorImports` `file` of `pkg` sees: `packageCtorImports` as its tests or as its other files do.
 */
public func ctorImportsOf(db: AnalysisDatabase, pkg: Package, file: SourceFile): CtorImports {
    packageCtorImports(db, pkg, isTestOf(db, pkg, file))
}

/**
 * The `CtorImports` of `pkg`: of its files' plain imports and of its re-exports; with `ofTests` false, of the files
 * that are no tests alone, which `cjpm build` compiles without the tests (N164).
 */
@CalcaTracked
public func packageCtorImports(db: AnalysisDatabase, pkg: Package, ofTests: Bool): CtorImports {
    let ctors = IndexMap<String, ArrayList<DefId>>()
    let globs = ArrayList<Glob>()
    let tests = pkg.testFiles(db)
    let files =
        pkg.files(db) |> filter { fileId: FileId => ofTests || !tests.contains(fileId) } |>
            filterMap { fileId => db.sourceFile(fileId, context: pkg) }
    let levels =
        (files |> map { file => fileImports(db, pkg, file) } |> collectArray)
            .concat([packageImports(db, resolutionPackage(db, pkg))])
    for (names in levels) {
        for ((name, ids) in names.ctors) {
            let entry = entryOf(ctors, name)
            for (id in ids where !entry.contains(id)) {
                entry.add(id)
            }
        }
        for (
            glob in names.globs where !globs
                .iterator()
                .any {
                    one =>
                    one.pkg == glob.pkg && one.relation == glob.relation && one.level == glob.level
                }
        ) {
            globs.add(Glob(glob.pkg, glob.relation, glob.level, None))
        }
    }
    CtorImports(frozen(ctors) { list => list.toArray() }, globs.toArray())
}

/**
 * What `name`, used in `ns`, means in the file `from` of the package of `defs`, its imports
 * `imports`, those of every file of the package `ctorImports`. The levels, the first that has it
 * deciding: the package's declarations (N13, N40, N49), the imports (N39, N42, N43), the
 * constructors (N45, N46), of the enums any file of the package imports (N73). Functions gather
 * over the first two (N14).
 */
public func lookUpIn(
    db: AnalysisDatabase,
    defs: DefMap,
    from: ItemFile,
    imports: ImportLevel,
    name: String,
    ns: Namespace,
    ctorImports!: CtorImports,
    source!: ?ItemFile = None
): Resolution {
    let own =
        (defs.names.get(name) ?? [])
            .filter {
                def =>
                (
                    def.visibility != Visibility.Private || def.id.file(db) == from ||
                        Some(def.id.file(db)) == source
                ) &&
                    isIn(def.id.item(db).kind, ns)
            }
            .map { def => def.id }
    let imported = ArrayList<ScopeTarget>()
    for (
        one in imports.names(db, name) where isIn(one.target, db, ns) &&
            !imported.contains(one.target)
    ) {
        imported.add(one.target)
    }
    if (!own.isEmpty()) {
        if (!own.iterator().all { id => id.item(db).kind == ItemKind.Func }) {
            return Resolution.Found(own)
        }
        let funcs = ArrayList<DefId>(own)
        for (target in imported) {
            if (
                let OfDecl(id) <- target && id.item(db).kind == ItemKind.Func && !funcs.contains(id)
            ) {
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
        if (imported.iterator().all { target => isFunc(target, db) }) {
            return Resolution
                .Found(
                    imported
                        .toArray()
                        .map {
                            target =>
                            match (target) {
                                case OfDecl(id) => id
                                case OfPackage(_) =>
                                    throw IllegalStateException("a package among functions")
                            }
                        }
                )
        }
        return Resolution.Ambiguous(imported.toArray())
    }
    if (ns != Namespace.Values) {
        return Resolution.NotFound
    }
    let ownCtors =
        (defs.ctors.get(name) ?? [])
            .filter { def => def.visibility != Visibility.Private || def.id.file(db) == from }
            .map { def => def.id }
    let ctorsOfImports = ctorImports.named(db, name)
    if (ownCtors.isEmpty() && ctorsOfImports.isEmpty()) {
        Resolution.NotFound
    } else {
        Resolution.Ctors(ownCtors, ctorsOfImports)
    }
}

/**
 * What `name`, used in `ns`, means in `file` of `pkg`. A query: inference and highlighting ask it of
 * every name, and a declaration added to the package runs again only what read a name it changes.
 */
@CalcaTracked
public func lookUp(
    db: AnalysisDatabase,
    pkg: Package,
    file: SourceFile,
    name: String,
    ns: Namespace
): Resolution {
    // a macro's name among what the files write: what is expanded depends on it (#175)
    let stage = if (ns == Namespace.Macros) { ScopeStage.Written } else { ScopeStage.Expanded }
    // constructors are values: a macro's lookup reads none
    let ctorImports =
        if (ns == Namespace.Values) {
            ctorImportsOf(db, pkg, file)
        } else {
            CtorImports(IndexMap<String, Array<DefId>>(), [])
        }
    lookUpIn(
        db,
        defMapAt(db, PackageRef.Source(pkg), stage),
        resolutionFile(db, file),
        importsAt(db, pkg, file, stage),
        name,
        ns,
        ctorImports: ctorImports,
        source: ItemFile.Source(file)
    )
}
