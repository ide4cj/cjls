package loupe.hir

import std.collection.*
import std.deriving.*
import calca.*
import calca.macros.*
import loupe.db.*
import loupe.vfs.VfsPath

/**
 * A package of the workspace cjls builds for the macro server to run its macros (#176): a macro package, or a source
 * package one imports, directly or not; its module, whose directory the build writes it into; the source packages it
 * links, those it imports directly or not, each built before it; and the `.cjo` of the binaries it imports so, other
 * than std's, which cjc finds itself.
 */
@Derive[Equatable]
public struct MacroBuildUnit {
    public MacroBuildUnit(
        public let pkg: Package,
        public let module: String,
        public let isMacro: Bool,
        public let deps: Array<Package>,
        public let binaries: Array<VfsPath>
    ) {}
}

/**
 * Whether `pkg` is a macro package: as the project model says, else as a `package` line of its files does.
 */
@CalcaTracked
public func isMacroPackage(db: AnalysisDatabase, pkg: Package): Bool {
    if (let Some(isMacro) <- pkg.isMacro(db)) {
        return isMacro
    }
    pkg
        .files(db)
        .iterator()
        .any {
            id =>
            db
                .sourceFile(id)
                .flatMap { file => itemTree(db, file).packageHeader }
                .map { header => header.isMacro } ??
                false
        }
}

/**
 * What cjls builds for the macro server, in the order to build it (#176): the macro packages of the workspace, each
 * after the source packages it imports, directly or not. A package importing one that imports it back is built after
 * those it was reached by alone.
 */
@CalcaTracked
public func macroBuildPlan(db: AnalysisDatabase): Array<MacroBuildUnit> {
    let project = db.project() ?? return []
    let modules = HashMap<Package, String>()
    for (module in project.modules(db)) {
        for (pkg in module.packages(db)) {
            modules[pkg] = module.name(db)
        }
    }
    let planner = MacroBuildPlanner(db, modules)
    for (module in project.modules(db)) {
        for (pkg in module.packages(db) where isMacroPackage(db, pkg)) {
            planner.visit(pkg)
        }
    }
    planner.units.toArray()
}

class MacroBuildPlanner {
    let units = ArrayList<MacroBuildUnit>()
    // what each package visited links: its source packages, then its binaries' `.cjo`, each once
    private let linked = HashMap<Package, (Array<Package>, Array<VfsPath>)>()
    private let visiting = HashSet<Package>()

    MacroBuildPlanner(
        private let db: AnalysisDatabase,
        private let modules: HashMap<Package, String>
    ) {}

    func visit(pkg: Package): (Array<Package>, Array<VfsPath>) {
        if (let Some(done) <- linked.get(pkg)) {
            return done
        }
        if (visiting.contains(pkg)) {
            return ([], [])
        }
        visiting.add(pkg)
        let deps = ArrayList<Package>()
        let binaries = ArrayList<VfsPath>()
        for (target in importedPackages(pkg)) {
            match (target) {
                case Source(dep) where modules.contains(dep) =>
                    let (depDeps, depBinaries) = visit(dep)
                    for (one in depDeps.concat([dep]) where !deps.contains(one)) {
                        deps.add(one)
                    }
                    for (one in depBinaries where !binaries.contains(one)) {
                        binaries.add(one)
                    }
                case Binary(file) where file.binary(db) != "std" &&
                        !binaries.contains(file.path(db)) => binaries.add(file.path(db))
                case _ => ()
            }
        }
        visiting.remove(pkg)
        let done = (deps.toArray(), binaries.toArray())
        linked[pkg] = done
        units
            .add(
                MacroBuildUnit(
                    pkg,
                    modules.get(pkg) ?? "",
                    isMacroPackage(db, pkg),
                    done[0],
                    done[1]
                )
            )
        done
    }

    /**
     * The packages the files of `pkg` import, each once, in the order they are first written.
     */
    private func importedPackages(pkg: Package): Array<PackageRef> {
        let found = ArrayList<PackageRef>()
        let from = PackageRef.Source(pkg)
        for (id in pkg.files(db)) {
            let file = db.sourceFile(id, context: pkg) ?? continue
            for (item in itemTree(db, file).imports) {
                for (path in item.paths) {
                    let target =
                        match (targetOf(db, from, path, Visibility.Private)) {
                            case PackageOf(_, target) => target
                            case GlobOf(target, _) => target
                            case NameOf(target, _, _, _) => target
                            case NoTarget(_) => continue
                        }
                    if (!found.contains(target)) {
                        found.add(target)
                    }
                }
            }
        }
        found.toArray()
    }
}
