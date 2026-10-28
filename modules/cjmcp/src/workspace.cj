package cjmcp

import std.collection.ArrayList
import std.env.getVariable
import std.fs.{canonicalize, exists, FileInfo, Path}
import loupe.db.AnalysisDatabase
import loupe.vfs.{Vfs, VfsPath, readCjoFiles, readFile}
import project_model.{
    findCangjieHome,
    findCangjieSrc,
    findProject,
    withCangjieHome,
    withCangjieSrc,
    withPackageCfgs
}

/**
 * One disk revision; replacing it on reload also discards cached queries for removed files.
 */
class WorkspaceState {
    let db = AnalysisDatabase()
    let vfs = Vfs()
    let files: Array<VfsPath>
    let problems: Array<String>

    WorkspaceState(let root: VfsPath) {
        if (
            !exists(root.toString()) || !FileInfo(canonicalize(Path(root.toString()))).isDirectory()
        ) {
            throw IllegalArgumentException("workspace directory does not exist: ${root}")
        }
        let found = findCangjieHome(None, env: getVariable)
        let homeEnv = withCangjieHome(getVariable, found)
        let env = withCangjieSrc(homeEnv, findCangjieSrc(None, env: homeEnv))
        let load = findProject(root, env: env)
        let issues = ArrayList<String>(load.problems)
        let model = withPackageCfgs(load.model, issues)
        let binaries = readCjoFiles(model.cjoFiles())
        issues.add(all: binaries.problems)
        db.setProject(model, vfs.paths, binaries: binaries.files)
        files = model.files()
        for (path in files.concat(model.binarySourceFiles())) {
            match (readFile(path)) {
                case Some(text) => vfs.setFileContents(path, text)
                case None => issues.add("could not read ${path}")
            }
        }
        db.applyChanges(vfs, vfs.takeChanges())
        problems = issues.toArray()
    }
}
