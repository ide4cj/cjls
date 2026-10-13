package cjls.macro_host

import std.collection.*
import std.fs.*
import loupe.db.*
import loupe.hir.MacroBuildUnit
import loupe.vfs.VfsPath

/**
 * `plan` split by where it is built (D104): for each directory `outOf` gives a macro package, its project's
 * `macro-build/<cjc --version>`, the macro packages it gives it and the source packages they link, in the plan's
 * order. A source package of another project is built into the importer's directory as well: no build reads another
 * project's. A macro package `outOf` gives none is left out.
 */
func groupsOf(plan: Array<MacroBuildUnit>, outOf: (Package) -> ?Path): Array<(Path, Array<MacroBuildUnit>)> {
    let outs = ArrayList<Path>()
    let needed = HashMap<String, HashSet<Package>>()
    for (unit in plan where unit.isMacro) {
        let out = outOf(unit.pkg) ?? continue
        let key = out.toString()
        if (!needed.contains(key)) {
            outs.add(out)
            needed[key] = HashSet<Package>()
        }
        needed[key].add(unit.pkg)
        needed[key].add(all: unit.deps)
    }
    outs.toArray().map {out => (out, plan.filter {unit => needed[out.toString()].contains(unit.pkg)})}
}

/**
 * What building a group gave a macro package: its name, and its library or why there is none.
 */
struct GroupResult {
    GroupResult(let name: String, let library: BuiltLibrary) {}
}

/**
 * Builds `plan`, each group of `groupsOf` into its directory under that directory's lock: what each macro package
 * built gave, by its directory, which two projects naming their packages alike do not share; and whether every
 * group was built, `false` if another server held the lock of one, which is left as it was.
 */
func buildPlan(db: AnalysisDatabase, plan: Array<MacroBuildUnit>, outOf: (Package) -> ?Path, version: String,
    toolchain: Toolchain): (HashMap<VfsPath, GroupResult>, Bool) {
    let modules = HashMap<Package, String>()
    for (unit in plan) {
        modules[unit.pkg] = unit.module
    }
    let results = HashMap<VfsPath, GroupResult>()
    var all = true
    for ((out, group) in groupsOf(plan, outOf)) {
        let units = ArrayList<BuildUnit>()
        for (unit in group) {
            let dir = unit.pkg.dir(db).filePath ?? continue
            units.add(BuildUnit(unit.pkg.name(db), unit.module, dir, unit.isMacro,
                unit.deps.map {dep => (modules.get(dep) ?? unit.module, dep.name(db))},
                unit.binaries |> filterMap {cjo: VfsPath => cjo.filePath} |> collectArray))
        }
        let built = try {
            MacroBuilder(out, version, toolchain).build(units.toArray())
        } catch (e: FSException) {
            let failed = HashMap<String, BuiltLibrary>()
            for (unit in units where unit.isMacro) {
                failed[unit.name] = NotBuilt("${out} cannot be written: ${e.message}")
            }
            Some(failed)
        }
        match (built) {
            case Some(byName) => for (unit in group where unit.isMacro) {
                let name = unit.pkg.name(db)
                if (let Some(library) <- byName.get(name)) {
                    results[unit.pkg.dir(db)] = GroupResult(name, library)
                }
            }
            case None => all = false
        }
    }
    (results, all)
}
