package project_model

import std.collection.*
import loupe.db.*
import loupe.vfs.{isCangjieFile, VfsPath}

/**
 * The projects of the Cangjie files of `files` that `model` covers none of, each file with the name
 * its `package` line gives (`None` for none): each compiled alone, as `cjc file.cj` compiles it
 * (#293). A file is a module of its own, rooted at the file as a program is (D67) and named after its
 * root package; its one package holds it alone, named by its line, `default` without one; it imports
 * `std` alone, nothing of `model`. A path of no directory is none.
 */
public func loneFileProjects(model: ProjectModel, files: Array<(VfsPath, ?String)>, env!: (String) -> ?String,
    cfg!: Cfg = hostCfg()): Array<ProjectLoad> {
    let alone = files.filter {file => isCangjieFile(file[0].name) && !model.covers(file[0])}
    if (alone.isEmpty()) {
        return []
    }
    // one `std` for all of them: its sources are listed once
    let loading = Loading(env, cfg)
    let binaries: Array<BinaryModel> = match (loading.stdBinary()) {
        case Some(std) => [std]
        case None => []
    }
    let loads = ArrayList<ProjectLoad>()
    for ((path, header) in alone) {
        let dir = path.parent ?? continue
        let name = header ?? DEFAULT_PACKAGE
        let module = ModuleModel(moduleOf(name), path, [PackageModel(name, dir, [path])])
        loads.add(ProjectLoad(ProjectModel(cfg, [module], binaries: binaries), LoneFile(path),
            loading.problems.toArray()))
    }
    loads.toArray()
}
