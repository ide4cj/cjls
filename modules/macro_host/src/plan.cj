package macro_host

import std.collection.*
import std.fs.{FSException, Path}
import loupe.db.*
import loupe.hir.MacroBuildUnit
import loupe.vfs.VfsPath

/**
 * What building a plan gave (`buildPlan`): for each macro package built or tried, its library or why there is none;
 * and the directories another server held the lock of, whose packages were left as they were.
 */
public class BuiltPlan {
    BuiltPlan(public let libraries: HashMap<Package, BuiltLibrary>, public let held: Array<Path>) {}
}

/**
 * `plan` split by where it is built (D104): for each directory `outs` gives a macro package, its own project's
 * `macro-build/<cjc --version>`, the macro packages it is given and the source packages they link, in the plan's
 * order. A source package of another project is built into the importer's directory too, so that no build reads a
 * directory it does not hold the lock of. A macro package `outs` gives none is left out.
 */
func groupsOf(
    plan: Array<MacroBuildUnit>,
    outs: HashMap<Package, Path>
): Array<(Path, Array<MacroBuildUnit>)> {
    let dirs = ArrayList<Path>()
    let needed = HashMap<String, HashSet<Package>>()
    for (unit in plan where unit.isMacro) {
        let out = outs.get(unit.pkg) ?? continue
        let key = out.toString()
        if (!needed.contains(key)) {
            dirs.add(out)
            needed[key] = HashSet<Package>()
        }
        needed[key].add(unit.pkg)
        needed[key].add(all: unit.deps)
    }
    dirs
        .toArray()
        .map { out => (out, plan.filter { unit => needed[out.toString()].contains(unit.pkg) }) }
}

/**
 * Builds `plan` with `toolchain` of the compiler `version`, each macro package into the directory `outOf` gives it,
 * its own project's, grouped by `groupsOf`, each group under that directory's lock (`MacroBuilder`): what each macro
 * package's build gave, by the package, which two projects naming their packages alike do not share. A group whose
 * lock another server holds is not built, and is named in `held`.
 */
public func buildPlan(
    db: AnalysisDatabase,
    plan: Array<MacroBuildUnit>,
    outOf: (Package) -> ?Path,
    version: String,
    toolchain: Toolchain
): BuiltPlan {
    let modules = HashMap<Package, String>()
    let outs = HashMap<Package, Path>()
    for (unit in plan) {
        modules[unit.pkg] = unit.module
        if (unit.isMacro && let Some(out) <- outOf(unit.pkg)) {
            outs[unit.pkg] = out
        }
    }
    let libraries = HashMap<Package, BuiltLibrary>()
    let held = ArrayList<Path>()
    for ((out, group) in groupsOf(plan, outs)) {
        let units = ArrayList<BuildUnit>()
        for (unit in group) {
            let dir = unit.pkg.dir(db).filePath ?? continue
            units
                .add(
                    BuildUnit(
                        unit.pkg.name(db),
                        unit.module,
                        dir,
                        unit.isMacro,
                        unit.deps.map { dep => (modules.get(dep) ?? unit.module, dep.name(db)) },
                        unit.binaries |> filterMap { cjo: VfsPath => cjo.filePath } |> collectArray
                    )
                )
        }
        let built =
            try {
                MacroBuilder(out, version, toolchain).build(units.toArray())
            } catch (e: FSException) {
                let failed = HashMap<String, BuiltLibrary>()
                for (unit in units where unit.isMacro) {
                    failed[unit.name] = NotBuilt("${out} cannot be written: ${e.message}")
                }
                Some(failed)
            }
        match (built) {
            // only the group's own: a macro package another imports is the library of its own directory. By name,
            // which one project's packages do not share
            case Some(byName) =>
                for (
                    unit in group where unit.isMacro &&
                        outs.get(unit.pkg)?.toString() == Some(out.toString())
                ) {
                    if (let Some(library) <- byName.get(unit.pkg.name(db))) {
                        libraries[unit.pkg] = library
                    }
                }
            case None => held.add(out)
        }
    }
    BuiltPlan(libraries, held.toArray())
}
