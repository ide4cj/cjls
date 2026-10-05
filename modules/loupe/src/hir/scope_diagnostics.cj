package loupe.hir

import std.collection.*
import std.deriving.*
import calca.*
import calca.macros.*
import index_map.IndexMap
import loupe.db.{AnalysisDatabase, Package, SourceFile}

/**
 * What is wrong with a file's scope, as cjc and cjpm report it.
 */
@Derive[Equatable]
public enum ScopeProblem <: ToString {
    /**
     * A path of an import that brings nothing, or that closes a cycle of packages (N36, N47).
     */
    | ImportFailed(ImportError)
    /**
     * A name imported by its path that a declaration of the package, not a function, shadows
     * (N13, N40, N43): a warning.
     */
    | Shadowed(String)
    /**
     * A name imported by its path that another path of the file imported before: a warning, the
     * use deciding (N17, N48).
     */
    | Conflicted(String)
    /**
     * A declaration named like a package under its own (N30).
     */
    | SubPackage(String, String)

    public func toString(): String {
        match (this) {
            case ImportFailed(error) => "error: ${error}"
            case Shadowed(name) => "warning: imported decl '${name}' is shadowed"
            case Conflicted(name) => "warning: imported decl '${name}' is conflicted with other import"
            case SubPackage(name, pkg) => "error: top-level declaration '${name}' is conflicted with possible sub-package '${pkg}'"
        }
    }
}

/**
 * Where a problem is: a path of an import, or a name of a declaration.
 */
@Derive[Equatable]
public enum ScopeProblemAt {
    | AtImport(ImportSite)
    | AtDecl(DefId, String)
}

@Derive[Equatable]
public struct ScopeDiagnostic {
    public ScopeDiagnostic(public let at: ScopeProblemAt, public let problem: ScopeProblem) {}
}

/**
 * Whether `pkg` is on a cycle of packages importing one another (N36), which cjpm rejects: an
 * import is a package's whole reading of another, so the cycle is one of this query.
 */
@CalcaTracked[cycleResult: onImportCycleFallback]
public func onImportCycle(db: AnalysisDatabase, pkg: PackageRef): Bool {
    for (file in filesOf(db, pkg)) {
        for (item in itemTreeOf(db, file).imports) {
            for (path in item.paths) {
                if (let Some(target) <- packageOf(targetOf(db, pkg, path, importLevelOf(item)))) {
                    onImportCycle(db, target)
                }
            }
        }
    }
    false
}

/**
 * The package an import's path names, `None` if it names none.
 */
func packageOf(target: ImportTarget): ?PackageRef {
    match (target) {
        case PackageOf(_, pkg) => pkg
        case GlobOf(pkg, _) => pkg
        case NameOf(pkg, _, _, _) => pkg
        case NoTarget(_) => None
    }
}

func onImportCycleFallback(_: AnalysisDatabase, _: PackageRef): Bool {
    true
}

/**
 * What is wrong with the scope of `file`, of `pkg`: its imports, in their order, then its
 * declarations named like a package under its own.
 */
@CalcaTracked
public func scopeDiagnostics(db: AnalysisDatabase, pkg: Package, file: SourceFile): Array<ScopeDiagnostic> {
    let from = PackageRef.Source(pkg)
    let own = ItemFile.Source(file)
    let defs = defMap(db, from)
    let cyclic = onImportCycle(db, from)
    let found = ArrayList<ScopeDiagnostic>()
    let brought = HashSet<String>()
    let tree = itemTree(db, file)
    for (item in tree.imports) {
        let level = importLevelOf(item)
        for (i in 0..item.paths.size) {
            let at = ScopeProblemAt.AtImport(ImportSite(own, item.id, i, level))
            let target = targetOf(db, from, item.paths[i], level)
            // what the path brings by its own name, and what is wrong with it
            let result: (?ScopeProblem, ?String) = match (target) {
                case PackageOf(name, _) => (None, name)
                case GlobOf(pkgOfGlob, full) =>
                    if (packageExports(db, pkgOfGlob).cyclic) {
                        (ScopeProblem.ImportFailed(ImportError.Cycle(full)), None)
                    } else {
                        (None, None)
                    }
                case NameOf(pkgOfName, pkgName, name, alias) =>
                    match (namesOf(db, from, pkgOfName, pkgName, level, (name, alias))) {
                        case Unresolved(error) => (ScopeProblem.ImportFailed(error), None)
                        case _ => (None, alias ?? name)
                    }
                case NoTarget(error) => (ScopeProblem.ImportFailed(error), None)
            }
            var problem = result[0]
            // a cycle through plain imports: this package and the one imported both on one
            if (problem.isNone() && cyclic) {
                if (let Some(imported) <- packageOf(target) && onImportCycle(db, imported)) {
                    problem = ScopeProblem.ImportFailed(ImportError.Cycle(nameOf(db, imported)))
                }
            }
            if (let Some(wrong) <- problem) {
                found.add(ScopeDiagnostic(at, wrong))
            }
            if (let Some(name) <- result[1]) {
                if (!brought.add(name)) {
                    found.add(ScopeDiagnostic(at, ScopeProblem.Conflicted(name)))
                }
                let shadowing = (defs.names.get(name) ?? []).iterator().any {
                    def => (def.visibility != Visibility.Private || def.id.file(db) == own) &&
                        def.id.item(db).kind != ItemKind.Func
                }
                if (shadowing) {
                    found.add(ScopeDiagnostic(at, ScopeProblem.Shadowed(name)))
                }
            }
        }
    }
    // N30
    let pkgName = pkg.name(db)
    let index = packageIndex(db)
    for (item in tree.items) {
        for (name in item.names) {
            let sub = "${pkgName}.${name}"
            if (let Some(Source(_)) <- index.find(sub, from: from)) {
                found.add(ScopeDiagnostic(ScopeProblemAt.AtDecl(DefId(db, own, item.id), name),
                    ScopeProblem.SubPackage(name, sub)))
            }
        }
    }
    found.toArray()
}
