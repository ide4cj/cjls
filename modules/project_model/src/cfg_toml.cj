package project_model

import std.collection.*
import std.fs.*
import ftoml.*
import loupe.db.*
import loupe.vfs.VfsPath

/**
 * The file of a package's own conditions, in its directory.
 */
public const CFG_TOML = "cfg.toml"

/**
 * `model` with the `cfg.toml` of each package's directory read into its `cfg`, as cjc reads the one
 * of the package it compiles when no `--cfg` says otherwise (cjpm passes it none, `-p` the
 * package's directory): `key = "value"`, each a condition `@When` may name (#149). One that cannot
 * be read, or is not of strings, is left out, and said in `problems`.
 */
public func withPackageCfgs(model: ProjectModel, problems: ArrayList<String>): ProjectModel {
    let modules = model.modules.map {
        module => ModuleModel(module.name, module.root, module.packages.map {
            pkg => match (cfgTomlOf(pkg.dir, problems)) {
                case Some(cfg) => PackageModel(pkg.name, pkg.dir, pkg.files, noPrelude: pkg.noPrelude,
                    isMacro: pkg.isMacro, cfg: cfg)
                case None => pkg
            }
        }, deps: module.deps, member: module.member, cfg: module.cfg, inactive: module.inactive)
    }
    ProjectModel(model.cfg, modules, binaries: model.binaries)
}

/**
 * The conditions of the `cfg.toml` in `dir`, `None` if there is none or it cannot be read.
 */
func cfgTomlOf(dir: VfsPath, problems: ArrayList<String>): ?Cfg {
    let file = dir.join(CFG_TOML)
    let path = file.filePath ?? return None
    if (!isFile(path)) {
        return None
    }
    try {
        Cfg(fromTomlBytes<HashMap<String, String>>(File.readFrom(path)).toArray())
    } catch (e: FSException) {
        problems.add("${file}: ${e.message}")
        None
    } catch (e: Exception) {
        problems.add("${file}: not conditions of `@When`, `key = \"value\"`: ${e.message}")
        None
    }
}
