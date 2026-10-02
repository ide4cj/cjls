package project_model

import std.collection.*
import std.fs.*
import std.sort.*
import fjson.*
import loupe.db.*
import loupe.vfs.{isCangjieFile, isScanned, VfsPath}

/**
 * Where a project was found.
 */
public enum ProjectSource <: ToString {
    /**
     * A `cj-project.json`, at this path.
     */
    | ProjectFile(VfsPath)
    /**
     * A `cjpm.toml`, at this path.
     */
    | CjpmManifest(VfsPath)
    /**
     * Neither: the `*.cj` under this directory, a package per `package` line.
     */
    | LooseFiles(VfsPath)

    public func toString(): String {
        match (this) {
            case ProjectFile(path) => "${PROJECT_JSON} at ${path}"
            case CjpmManifest(path) => "cjpm.toml at ${path}"
            case LooseFiles(path) => "loose files under ${path}"
        }
    }
}

/**
 * A project found, where, and what was wrong on the way: a key that names nothing, a dependency
 * not there. None of it stops the load: what is missing is left out.
 */
public struct ProjectLoad {
    public ProjectLoad(public let model: ProjectModel, public let source: ProjectSource,
        public let problems: Array<String>) {}
}

/**
 * Thrown for a manifest that cannot be read: not there, not JSON or TOML, or not of the shape.
 */
public class ProjectException <: Exception {
    public ProjectException(message: String) {
        super(message)
    }

    protected override func getClassName(): String {
        "ProjectException"
    }
}

/**
 * What a load reads its paths and defaults against, and what it found wrong.
 */
class Loading {
    let problems = ArrayList<String>()

    Loading(let env: (String) -> ?String, let cfg: Cfg) {}

    /**
     * The path `text` names, `${VAR}` expanded, relative to `base` unless absolute.
     */
    func resolve(base: VfsPath, text: String): VfsPath {
        let expanded = expandVariables(text, env, problems)
        if (Path(expanded).isAbsolute()) {
            VfsPath.file(expanded)
        } else {
            base.join(expanded)
        }
    }

    /**
     * `std` from the SDK, as cjc finds it: `$CANGJIE_HOME/modules/<target>/std`.
     */
    func stdBinary(): ?BinaryModel {
        let home = match (env("CANGJIE_HOME")) {
            case Some(home) where Path(home).isAbsolute() => home
            case _ =>
                problems.add("`CANGJIE_HOME` is not set: `std` is not found")
                return None
        }
        let target = sdkTarget(cfg) ?? return None
        BinaryModel("std", [VfsPath.file(home).join("modules/${target}/std")])
    }
}

/**
 * The project of the directory `root`, the first that is there: its `cj-project.json`, its
 * `cjpm.toml`, or its loose files, of which at most `budget` bytes. A manifest that cannot be read
 * is told in the problems, and the next way is taken.
 *
 * `env` gives the value of an environment variable, for `${VAR}` and `CANGJIE_HOME`.
 */
public func findProject(root: VfsPath, env!: (String) -> ?String, cfg!: Cfg = hostCfg(),
    budget!: Int64 = Int64.Max): ProjectLoad {
    let problems = ArrayList<String>()
    for (load in [{=> loadProjectJson(root.join(PROJECT_JSON), env: env, cfg: cfg)},
        {=> loadCjpmProject(root.join("cjpm.toml"), env: env, cfg: cfg)}]) {
        try {
            if (let Some(found) <- load()) {
                problems.add(all: found.problems)
                return ProjectLoad(found.model, found.source, problems.toArray())
            }
        } catch (e: ProjectException) {
            problems.add(e.message)
        }
    }
    let loose = looseProject(root, env: env, cfg: cfg, budget: budget)
    problems.add(all: loose.problems)
    ProjectLoad(loose.model, loose.source, problems.toArray())
}

/**
 * The project the `cj-project.json` at `file` describes, `None` if there is no such file.
 *
 * @throws ProjectException - if it cannot be read
 */
public func loadProjectJson(file: VfsPath, env!: (String) -> ?String, cfg!: Cfg = hostCfg()): ?ProjectLoad {
    let path = file.filePath ?? return None
    if (!isFile(path)) {
        return None
    }
    let json = try {
        fromJsonBytes<ProjectJson>(File.readFrom(path))
    } catch (e: FSException) {
        throw ProjectException("${file}: ${e.message}")
    } catch (e: Exception) {
        throw ProjectException("${file}: not a project: ${e.message}")
    }
    let base = file.parent.getOrThrow()
    let loading = Loading(env, cfg)
    let model = lowerProjectJson(json, base, loading)
    ProjectLoad(model, ProjectFile(file), loading.problems.toArray())
}

/**
 * The project `json` describes, its paths relative to `base`.
 */
public func lowerProjectJson(json: ProjectJson, base: VfsPath, env!: (String) -> ?String,
    cfg!: Cfg = hostCfg()): ProjectModel {
    lowerProjectJson(json, base, Loading(env, cfg))
}

func lowerProjectJson(json: ProjectJson, base: VfsPath, loading: Loading): ProjectModel {
    let cfg = loading.cfg.overriddenBy(cfgOf(json.cfg))
    let modules = (json.modules ?? []).map {
        module =>
        let root = loading.resolve(base, module.root)
        let packages = match (module.packages) {
            case Some(packages) => packages.map {
                pkg =>
                let dir = match (pkg.dir) {
                    case Some(dir) => loading.resolve(base, dir)
                    case None => packageDir(module.name, root, pkg.name, loading)
                }
                let files = match (pkg.files) {
                    case Some(files) => files.map {file => loading.resolve(dir, file)}
                    case None => cangjieFilesIn(dir)
                }
                PackageModel(pkg.name, dir, files, noPrelude: pkg.noPrelude ?? false, isMacro: pkg.`macro`)
            }
            case None => packagesUnder(module.name, root)
        }
        ModuleModel(module.name, root, packages, deps: module.deps ?? [], member: module.member ?? true,
            cfg: module.cfg.map {own => cfg.overriddenBy(cfgOf(own))})
    }
    let binaries = ArrayList<BinaryModel>()
    // `std` is a module of the project, or a binary it names, or else the SDK's
    let named = (json.binaries ?? []).iterator().any {binary => binary.name == "std"}
    if (!named && !modules.iterator().any {module => module.name == "std"}) {
        if (let Some(std) <- loading.stdBinary()) {
            binaries.add(std)
        }
    }
    for (binary in json.binaries ?? []) {
        let packages = (binary.packages ?? HashMap<String, String>()).toArray().map {
            pkg => BinaryPackage(pkg[0], loading.resolve(base, pkg[1]))
        }
        sort(packages, by: {a, b => a.name.compare(b.name)})
        binaries.add(BinaryModel(binary.name, (binary.paths ?? []).map {path => loading.resolve(base, path)},
            packages: packages))
    }
    ProjectModel(cfg, modules, binaries: binaries.toArray())
}

/**
 * `model` as `cj-project.json` writes it, with everything a default would give written out: paths
 * relative to `base` where they are under it, absolute elsewhere.
 */
public func toProjectJson(model: ProjectModel, base: VfsPath): ProjectJson {
    let modules = model.modules.map {
        module => ModuleJson(
            name: module.name,
            root: relative(module.root, base),
            packages: module.packages.map {
                pkg => PackageJson(
                    name: pkg.name,
                    dir: relative(pkg.dir, base),
                    files: pkg.files.map {file => relative(file, pkg.dir)},
                    noPrelude: pkg.noPrelude,
                    `macro`: pkg.isMacro
                )
            },
            deps: module.deps,
            member: module.member,
            cfg: module.cfg.map {cfg => jsonOf(cfg)}
        )
    }
    let binaries = model.binaries.map {
        binary =>
        let packages = HashMap<String, String>()
        for (pkg in binary.packages) {
            packages.add(pkg.name, relative(pkg.path, base))
        }
        BinaryJson(name: binary.name, paths: binary.paths.map {path => relative(path, base)}, packages: packages)
    }
    ProjectJson(cfg: jsonOf(model.cfg), modules: modules, binaries: binaries)
}

/**
 * `path` as a path relative to `base`, `/`-separated, if it is under it; as it is otherwise.
 */
func relative(path: VfsPath, base: VfsPath): String {
    match (path.segmentsUnder(base)) {
        case Some(segments) where segments.isEmpty() => "."
        case Some(segments) => String.join(segments, delimiter: "/")
        case None => path.toString()
    }
}

func cfgOf(json: ?HashMap<String, String>): Cfg {
    Cfg((json ?? HashMap<String, String>()).toArray())
}

func jsonOf(cfg: Cfg): HashMap<String, String> {
    let json = HashMap<String, String>()
    for (option in cfg.options) {
        json.add(option.key, option.value)
    }
    json
}

/**
 * The directory of the package `name` of the module `module`, as cjpm lays them out: the module's
 * root, and a directory down per segment after the module's name.
 */
func packageDir(module: String, root: VfsPath, name: String, loading: Loading): VfsPath {
    if (name == module) {
        return root
    }
    if (!name.startsWith(module + ".")) {
        loading.problems.add("package `${name}` is not of module `${module}`: it is taken to be in ${root}")
        return root
    }
    root.join(name[module.size + 1..].replace(".", "/"))
}

/**
 * A package per directory under `root` holding a `*.cj`, `root` itself included, named as cjpm
 * names them: `<module>.<path>`. Directories are taken as `readRoots` takes them.
 */
public func packagesUnder(module: String, root: VfsPath): Array<PackageModel> {
    let packages = ArrayList<PackageModel>()
    collectPackages(module, root, packages)
    packages.toArray()
}

private func collectPackages(name: String, dir: VfsPath, packages: ArrayList<PackageModel>): Unit {
    let files = cangjieFilesIn(dir)
    if (!files.isEmpty()) {
        packages.add(PackageModel(name, dir, files))
    }
    for (sub in subdirectories(dir)) {
        collectPackages("${name}.${sub.name}", sub, packages)
    }
}

/**
 * The `*.cj` right in `dir`, in the order of their names; none if it cannot be listed.
 */
func cangjieFilesIn(dir: VfsPath): Array<VfsPath> {
    let files = entriesOf(dir).filter {entry => entry.isRegular() && isCangjieFile(entry.name)}.map {
        entry => VfsPath.file(entry.path)
    }
    sort(files, by: {a, b => a.toString().compare(b.toString())})
    files
}

/**
 * The directories right in `dir` a walk goes into, in the order of their names; links are not
 * followed.
 */
func subdirectories(dir: VfsPath): Array<VfsPath> {
    let dirs = entriesOf(dir).filter {
        entry => !entry.isSymbolicLink() && entry.isDirectory() && isScanned(entry.name)
    }.map {entry => VfsPath.file(entry.path)}
    sort(dirs, by: {a, b => a.toString().compare(b.toString())})
    dirs
}

/**
 * Whether a regular file is at `path`.
 */
func isFile(path: Path): Bool {
    try {
        exists(path) && FileInfo(path).isRegular()
    } catch (_: FSException) {
        false
    }
}

private func entriesOf(dir: VfsPath): Array<FileInfo> {
    let path = dir.filePath ?? return []
    try {
        Directory.readFrom(path)
    } catch (_: FSException) {
        []
    }
}

/**
 * The projects of `roots`, each the first there is: the `cj-project.json` in it, the projects of
 * `linked` under it, its `cjpm.toml`, its loose files. A project of `linked` (a `cj-project.json`,
 * or a directory to find one in) under no root is there too.
 */
public func findProjects(roots: Array<VfsPath>, linked: Array<VfsPath>, env!: (String) -> ?String,
    cfg!: Cfg = hostCfg(), budget!: Int64 = Int64.Max): Array<ProjectLoad> {
    let loads = ArrayList<ProjectLoad>()
    for (root in roots) {
        let under = linked.filter {path => path.isUnder(root)}
        if (under.isEmpty() || (root.join(PROJECT_JSON).filePath.map {path => isFile(path)} ?? false)) {
            loads.add(findProject(root, env: env, cfg: cfg, budget: budget))
        } else {
            loads.add(all: under.map {path => linkedProject(path, env, cfg, budget)})
        }
    }
    for (path in linked where !roots.iterator().any {root => path.isUnder(root)}) {
        loads.add(linkedProject(path, env, cfg, budget))
    }
    loads.toArray()
}

/**
 * The project `path` names: a `cj-project.json`, or a directory to find one in. One that cannot be
 * read is no project, and says why.
 */
func linkedProject(path: VfsPath, env: (String) -> ?String, cfg: Cfg, budget: Int64): ProjectLoad {
    let isProjectFile = path.filePath.map {file => isFile(file)} ?? false
    if (!isProjectFile) {
        return findProject(path, env: env, cfg: cfg, budget: budget)
    }
    try {
        if (let Some(load) <- loadProjectJson(path, env: env, cfg: cfg)) {
            return load
        }
    } catch (e: ProjectException) {
        return ProjectLoad(ProjectModel(cfg, []), ProjectFile(path), [e.message])
    }
    ProjectLoad(ProjectModel(cfg, []), ProjectFile(path), ["${path} is not there"])
}
