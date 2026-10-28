package project_model

import std.collection.*
import std.deriving.*
import std.fs.*
import std.sort.*
import ftoml.*
import stdxx.deriving.*
import loupe.db.*
import loupe.vfs.VfsPath

/**
 * The script cjpm runs around a build, beside its `cjpm.toml`.
 */
const BUILD_SCRIPT = "build.cj"

/**
 * The project of the `cjpm.toml` at `file`, `None` if there is no such file: a module per package
 * of the workspace, and one per source dependency, reached from them, which is no member; and one
 * per `build.cj`. A multiplatform module's packages are those of the chain of source sets the
 * target of `cfg` takes, the files of the others inactive (#318). A
 * Git or registry dependency is read from cjpm's locked cache; missing or stale locks and
 * downloaded sources are reported in the problems.
 *
 * @throws ProjectException - if the file cannot be read
 */
public func loadCjpmProject(
    file: VfsPath,
    env!: (String) -> ?String,
    cfg!: Cfg = hostCfg()
): ?ProjectLoad {
    let path = file.filePath ?? return None
    if (!isFile(path)) {
        return None
    }
    let loading = Loading(env, cfg)
    let manifest = readManifest(file)
    let dir = file.parent.getOrThrow()
    let lowering = CjpmLowering(loading, dir, manifest)
    for (member in lowering.members) {
        lowering.module(member)
    }
    // a workspace with no package of its own may still have a build script
    if (manifest.pkg.isNone()) {
        lowering.buildScript(dir, manifest, true)
    }
    let binaries = ArrayList<BinaryModel>()
    if (!lowering.modules.iterator().any { module => module.name == "std" }) {
        if (let Some(std) <- loading.stdBinary()) {
            binaries.add(std)
        }
    }
    binaries.add(all: lowering.binaries)
    let modules = lowering.modules.toArray()
    // Dependency build scripts can be visited before later ordinary dependencies.
    let ordered =
        modules
            .filter { module => module.resolutionScope.isEmpty() }
            .concat(modules.filter { module => !module.resolutionScope.isEmpty() })
    let model = ProjectModel(cfg, ordered, binaries: binaries.toArray())
    ProjectLoad(model, CjpmManifest(file), loading.problems.toArray())
}

/**
 * @throws ProjectException - if it cannot be read
 */
func readManifest(file: VfsPath): Manifest {
    let path = file.filePath.getOrThrow()
    try {
        fromTomlBytes<Manifest>(File.readFrom(path))
    } catch (e: FSException) {
        throw ProjectException("${file}: ${e.message}")
    } catch (e: Exception) {
        throw ProjectException("${file}: not a cjpm manifest: ${e.message}")
    }
}

/**
 * The modules of one workspace, as they are reached.
 */
class CjpmLowering {
    let modules = ArrayList<ModuleModel>()
    let binaries = ArrayList<BinaryModel>()
    /**
     * The directories of the workspace's packages: the root's own, then its members.
     */
    let members: Array<VfsPath>
    /**
     * The binaries every member may import: the workspace's own `bin-dependencies`.
     */
    private var workspaceBinaries = Array<String>()
    /**
     * The name of the module of each directory reached, `None` while it is being lowered, or if it
     * could not be.
     */
    private let reached = HashMap<CjpmDirectory, ?String>()
    private let selected = HashMap<CjpmSelection, VfsPath>()
    private let registrySelected = HashSet<CjpmSelection>()
    private let discovered = HashSet<CjpmDirectory>()
    private let pending = ArrayList<(String, Dependency, VfsPath, Bool)>()
    private let scripts = HashSet<VfsPath>()
    private let invalidReplacements = HashSet<String>()
    private let git: CjpmGit
    private let registry: CjpmRegistry

    CjpmLowering(
        private let loading: Loading,
        private let root: VfsPath,
        private let manifest: Manifest
    ) {
        git = CjpmGit(loading, root)
        registry = CjpmRegistry(loading, root)
        let members = ArrayList<VfsPath>()
        if (manifest.pkg.isSome()) {
            members.add(root)
        }
        for (member in manifest.workspace.flatMap { workspace => workspace.members } ?? []) {
            members.add(loading.resolve(root, member))
        }
        this.members = members.toArray()
        validateReplacements()
        if (manifest.workspace.isSome()) {
            workspaceBinaries = binaryDeps(manifest, root)
        }
        for (member in this.members) {
            discover(member, false)
        }
        if (manifest.pkg.isNone()) {
            discoverScripts(root, manifest)
        }
        // Local and Git modules take precedence over registry requirements, even if a
        // registry declaration sorts first. Only reached requirements are resolved.
        var index = 0
        while (index < pending.size) {
            let (name, dep, base, script) = pending[index]
            index++
            if (
                !selected.contains(CjpmSelection(script, name)) ||
                    registrySelected.contains(CjpmSelection(script, name))
            ) {
                selectDependency(name, dep, base, script, registry: true)
            }
        }
    }

    /** cjpm validates replacement versions even when no dependency reaches them. */
    private func validateReplacements(): Unit {
        for ((name, dep) in manifest.replace ?? HashMap<String, Dependency>()) {
            let version =
                match (dep) {
                    case Version(text) => Some(text)
                    case Table(table) where table.path.isNone() && table.git.isNone() =>
                        table.version
                    case _ => Option<String>.None
                }
            if (let Some(text) <- version) {
                try {
                    registryVersion(text)
                } catch (_: Exception) {
                    invalidReplacements.add(name)
                    loading
                        .problems
                        .add(
                            "Entry [replace] `${name}` must select a single registry version, not `${text}`; update cjpm.toml and run `cjpm update`."
                        )
                }
            }
        }
    }

    private func discover(dir: VfsPath, script: Bool): Unit {
        if (!discovered.add(CjpmDirectory(script, dir))) {
            return
        }
        try {
            let manifest =
                if (dir == root) { this.manifest } else { readManifest(dir.join("cjpm.toml")) }
            if (let Some(pkg) <- manifest.pkg) {
                let name = packageName(pkg)
                let key = CjpmSelection(script, name)
                if (let Some(previous) <- selected.get(key)) {
                    if (previous != dir) {
                        loading
                            .problems
                            .add(
                                "Conflicting workspace module `${name}`: ${previous} and ${dir}; keeping ${previous}."
                            )
                        return
                    }
                } else {
                    selected[key] = dir
                }
            }
            for ((name, dep) in dependencies(manifest)) {
                selectDependency(name, dep, dir, script)
            }
            discoverScripts(dir, manifest)
        } catch (e: ProjectException) {
            loading.problems.add(e.message)
        }
    }

    private func discoverScripts(dir: VfsPath, manifest: Manifest): Unit {
        if (!(dir.join(BUILD_SCRIPT).filePath.map { path => isFile(path) } ?? false)) {
            return
        }
        let sorted = (manifest.scriptDependencies ?? HashMap<String, Dependency>()).toArray()
        sort(sorted, by: { a, b => a[0].compare(b[0]) })
        for ((name, dep) in sorted) {
            selectDependency(name, dep, dir, true)
        }
    }

    private func selectDependency(
        name: String,
        declared: Dependency,
        base: VfsPath,
        script: Bool,
        registry!: Bool = false
    ): Unit {
        if (!script && invalidReplacements.contains(name)) {
            return
        }
        let replacement =
            if (script) {
                Option<Dependency>.None
            } else {
                manifest.replace.flatMap { all => all.get(name) }
            }
        let dep = replacement ?? declared
        let dir = if (replacement.isSome()) { root } else { base }
        let local =
            match (dep) {
                case Table(table) => table.path.isSome() || table.git.isSome()
                case _ => false
            }
        if (!local && !registry) {
            pending.add((name, declared, base, script))
            return
        }
        let path =
            match (dep) {
                case Table(table) where table.path.isSome() =>
                    Some(loading.resolve(dir, table.path.getOrThrow()))
                case Table(table) where table.git.isSome() =>
                    git.resolve(name, table, script: script)
                case _ => this.registry.resolve(name, dep, script: script)
            } ??
                return
        let key = CjpmSelection(script, name)
        if (let Some(previous) <- selected.get(key)) {
            if (previous == path) {
                return
            }
            if (!registrySelected.contains(key)) {
                if (local) {
                    let scope = if (script) { "build-script" } else { "ordinary/test" }
                    let remedy =
                        if (script) {
                            "Align script dependency declarations"
                        } else {
                            "Use entry [replace] to select one source"
                        }
                    loading
                        .problems
                        .add(
                            "Conflicting ${scope} dependency `${name}`: ${previous} and ${path}; keeping ${previous}. ${remedy}, then run `cjpm update`."
                        )
                }
                return
            }
        }
        try {
            let pkg =
                readManifest(path.join("cjpm.toml")).pkg ??
                    throw ProjectException("${path} has no [package]")
            if (packageName(pkg) != name) {
                throw ProjectException(
                    "${path} declares `${packageName(pkg)}`, expected dependency `${name}`"
                )
            }
        } catch (e: ProjectException) {
            loading.problems.add(e.message)
            return
        }
        selected[key] = path
        if (local) { registrySelected.remove(key) } else { registrySelected.add(key) }
        discover(path, script)
    }

    /**
     * The name of the module in `dir`, lowered the first time; `None` if it has no manifest, or
     * no package.
     */
    func module(dir: VfsPath, forScript!: Bool = false): ?String {
        let key = CjpmDirectory(forScript, dir)
        if (let Some(name) <- reached.get(key)) {
            return name
        }
        reached.add(key, None)
        let manifest =
            if (dir == root) {
                this.manifest
            } else {
                try {
                    readManifest(dir.join("cjpm.toml"))
                } catch (e: ProjectException) {
                    loading.problems.add(e.message)
                    return None
                }
            }
        let pkg =
            match (manifest.pkg) {
                case Some(pkg) => pkg
                case None =>
                    loading.problems.add("${dir.join("cjpm.toml")} has no [package]")
                    return None
            }
        let name =
            match (pkg.organization) {
                case Some(org) where !org.trimAscii().isEmpty() => "${org.trimAscii()}::${pkg.name}"
                case _ => pkg.name
            }
        if (let Some(chosen) <- selected.get(CjpmSelection(forScript, name)) && chosen != dir) {
            let result = module(chosen, forScript: forScript)
            reached.add(key, result)
            return result
        }
        reached.add(key, name)
        let deps = ArrayList<String>()
        for ((key, _) in dependencies(manifest)) {
            if (let Some(path) <- selected.get(CjpmSelection(forScript, key))) {
                if (let Some(name) <- module(path, forScript: forScript)) {
                    deps.add(name)
                }
            }
        }
        let member = !forScript && members.contains(dir)
        if (member) {
            deps.add(all: workspaceBinaries)
        }
        deps.add(all: binaryDeps(manifest, dir))
        let unique = ArrayList<String>()
        for (dep in deps where !unique.contains(dep)) {
            unique.add(dep)
        }
        // under `src-dir = "."` the build script is beside the sources, and cjpm leaves it out of them
        let script = dir.join(BUILD_SCRIPT)
        let (sources, found, inactive) = sourcesOf(name, dir, manifest, pkg)
        let packages = ArrayList<PackageModel>()
        for (pkg in found) {
            let files = pkg.files.filter { file => file != script }
            if (!files.isEmpty()) {
                packages
                    .add(
                        PackageModel(
                            pkg.name,
                            pkg.dir,
                            files,
                            noPrelude: pkg.noPrelude,
                            isMacro: pkg.isMacro
                        )
                    )
            }
        }
        modules
            .add(
                ModuleModel(
                    name,
                    sources,
                    packages.toArray(),
                    deps: unique.toArray(),
                    member: member,
                    inactive: inactive.filter { file => file.path != script },
                    resolutionScope: if (forScript) { scriptScope } else { "" }
                )
            )
        buildScript(dir, manifest, member)
        name
    }

    /**
     * Where the packages of the module `name` in `dir` are, and they themselves, and the files the
     * build leaves out. Its `src-dir`, if it has no source sets; else the chain of those the target
     * takes, its first set's directory the root, a package the files of each set of the chain,
     * named after its directory under the set's, in the directory of the first (#318). The files of
     * the sets left out are inactive, each with why.
     */
    private func sourcesOf(
        name: String,
        dir: VfsPath,
        manifest: Manifest,
        pkg: ManifestPackage
    ): (VfsPath, Array<PackageModel>, Array<InactiveFile>) {
        let sets = manifest.sourceSets ?? []
        if (sets.isEmpty()) {
            let srcDir =
                match (pkg.srcDir) {
                    case Some(src) where !src.trimAscii().isEmpty() => src.trimAscii()
                    case _ => "src"
                }
            let sources = loading.resolve(dir, srcDir)
            return (sources, packagesUnder(name, sources), [])
        }
        let picked =
            sourceSetChain(
                sets,
                manifest.featureTables ?? [],
                loading.cfg,
                always: pkg.alwaysEnabledFeatures ?? []
            )
        loading.problems.add(all: picked.problems)
        let merged = ArrayList<(String, VfsPath, ArrayList<VfsPath>)>()
        for (set in picked.chain) {
            for (one in packagesUnder(name, loading.resolve(dir, set.srcDir))) {
                match (merged.iterator().filter { kept => kept[0] == one.name }.next()) {
                    case Some((_, _, files)) => files.add(all: one.files)
                    case None => merged.add((one.name, one.dir, ArrayList<VfsPath>(one.files)))
                }
            }
        }
        let inactive = ArrayList<InactiveFile>()
        for ((set, reason) in picked.left) {
            for (one in packagesUnder(name, loading.resolve(dir, set.srcDir))) {
                inactive.add(all: one.files.map { file => InactiveFile(file, reason) })
            }
        }
        let root = picked.chain.get(0).map { set => loading.resolve(dir, set.srcDir) } ?? dir
        (
            root,
            merged.toArray().map { one => PackageModel(one[0], one[1], one[2].toArray()) },
            inactive.toArray()
        )
    }

    /**
     * The `build.cj` beside `manifest`, in `dir`, as a module of its own: cjpm compiles it alone,
     * a program of the package `default`, which sees `std` and the manifest's
     * `script-dependencies`, not the code it builds.
     */
    func buildScript(dir: VfsPath, manifest: Manifest, member: Bool): Unit {
        let script = dir.join(BUILD_SCRIPT)
        if (!(script.filePath.map { path => isFile(path) } ?? false) || !scripts.add(dir)) {
            return
        }
        let deps = ArrayList<String>()
        let sorted = (manifest.scriptDependencies ?? HashMap<String, Dependency>()).toArray()
        sort(sorted, by: { a, b => a[0].compare(b[0]) })
        for ((key, _) in sorted) {
            if (let Some(path) <- selected.get(CjpmSelection(true, key))) {
                if (let Some(name) <- module(path, forScript: true)) {
                    deps.add(name)
                }
            }
        }
        modules
            .add(
                ModuleModel(
                    DEFAULT_PACKAGE,
                    dir,
                    [PackageModel(DEFAULT_PACKAGE, dir, [script])],
                    deps: deps.toArray(),
                    member: member,
                    resolutionScope: scriptScope
                )
            )
    }

    /**
     * Every dependency of `manifest` for the target, test ones included, in the order of their
     * names.
     */
    private func dependencies(manifest: Manifest): Array<(String, Dependency)> {
        let all = HashMap<String, Dependency>()
        let target = targetOf(manifest)
        for (
            table in [
                manifest.dependencies,
                manifest.testDependencies,
                target.flatMap { it => it.dependencies },
                target.flatMap { it => it.testDependencies }
            ]
        ) {
            all.add(all: table ?? HashMap<String, Dependency>())
        }
        let sorted = all.toArray()
        sort(sorted, by: { a, b => a[0].compare(b[0]) })
        sorted
    }

    /**
     * The names of the binaries `manifest` names for the target, each added to the project the
     * first time: one per directory of `path-option`, named as the directory is, and one per
     * module of `package-option`.
     */
    private func binaryDeps(manifest: Manifest, dir: VfsPath): Array<String> {
        let bin = targetOf(manifest).flatMap { target => target.binDependencies } ?? return []
        let names = ArrayList<String>()
        for (option in bin.pathOption ?? []) {
            let path = loading.resolve(dir, option)
            names.add(path.name)
            addBinary(BinaryModel(path.name, [path]))
        }
        let byModule = HashMap<String, ArrayList<BinaryPackage>>()
        for ((pkg, cjo) in bin.packageOption ?? HashMap<String, String>()) {
            let module = moduleOf(pkg)
            if (!byModule.contains(module)) {
                byModule.add(module, ArrayList<BinaryPackage>())
            }
            byModule[module].add(BinaryPackage(pkg, loading.resolve(dir, cjo)))
        }
        let modules = byModule.keys().toArray()
        sort(modules)
        for (module in modules) {
            let packages = byModule[module].toArray()
            sort(packages, by: { a, b => a.name.compare(b.name) })
            names.add(module)
            addBinary(BinaryModel(module, [], packages: packages))
        }
        names.toArray()
    }

    private func addBinary(binary: BinaryModel): Unit {
        if (!binaries.iterator().any { kept => kept.name == binary.name }) {
            binaries.add(binary)
        }
    }

    private prop scriptScope: String {
        get() {
            "${root}#scripts"
        }
    }

    private func targetOf(manifest: Manifest): ?Target {
        let triple = cjpmTriple(loading.cfg) ?? return None
        manifest.target.flatMap { targets => targets.get(triple) }
    }
}

/**
 * The module a package is of: its root package, the name up to the first `.` (`org::a.b` is of
 * `org::a`).
 */
public func moduleOf(pkg: String): String {
    match (pkg.indexOf(".")) {
        case Some(dot) => pkg[..dot]
        case None => pkg
    }
}

/**
 * What the project needs of a `cjpm.toml`; the rest is skipped.
 */
@DeriveExt[FromToml]
struct Manifest {
    Manifest(
        @Serde[rename: "package"]
        let pkg!: ?ManifestPackage = None,
        let workspace!: ?Workspace = None,
        let dependencies!: ?HashMap<String, Dependency> = None,
        let replace!: ?HashMap<String, Dependency> = None,
        @Serde[rename: "test-dependencies"]
        let testDependencies!: ?HashMap<String, Dependency> = None,
        @Serde[rename: "script-dependencies"]
        let scriptDependencies!: ?HashMap<String, Dependency> = None,
        let target!: ?HashMap<String, Target> = None,
        @Serde[rename: "source-set"]
        let sourceSets!: ?Array<SourceSet> = None,
        // not `features`: see `SourceSet.featureNames`
        @Serde[rename: "feature"]
        let featureTables!: ?Array<Feature> = None
    ) {}
}

@DeriveExt[FromToml]
struct ManifestPackage {
    ManifestPackage(
        let name!: String,
        let organization!: ?String = None,
        let version!: ?String = None,
        @Serde[rename: "src-dir"]
        let srcDir!: ?String = None,
        @Serde[rename: "always-enabled-features"]
        let alwaysEnabledFeatures!: ?Array<String> = None
    ) {}
}

@DeriveExt[FromToml]
struct Workspace {
    Workspace(let members!: ?Array<String> = None) {}
}

/**
 * A dependency: a version, or a table saying where it is.
 */
@DeriveExt[FromToml]
@Serde[untagged]
enum Dependency {
    | Version(String)
    | Table(DependencyTable)
}

@DeriveExt[FromToml]
struct DependencyTable {
    DependencyTable(
        let path!: ?String = None,
        let git!: ?String = None,
        let branch!: ?String = None,
        let tag!: ?String = None,
        let commitId!: ?String = None,
        let source!: ?String = None,
        let version!: ?String = None,
        let checksum!: ?String = None
    ) {}
}

/**
 * `[target.<triple>]`.
 */
@DeriveExt[FromToml]
struct Target {
    Target(
        let dependencies!: ?HashMap<String, Dependency> = None,
        @Serde[rename: "test-dependencies"]
        let testDependencies!: ?HashMap<String, Dependency> = None,
        @Serde[rename: "bin-dependencies"]
        let binDependencies!: ?BinDependencies = None
    ) {}
}

@DeriveExt[FromToml]
struct BinDependencies {
    BinDependencies(
        @Serde[rename: "path-option"]
        let pathOption!: ?Array<String> = None,
        @Serde[rename: "package-option"]
        let packageOption!: ?HashMap<String, String> = None
    ) {}
}

@Derive[Hashable, Equatable]
struct CjpmDirectory {
    CjpmDirectory(let script: Bool, let dir: VfsPath) {}
}

@Derive[Hashable, Equatable]
struct CjpmSelection {
    CjpmSelection(let script: Bool, let name: String) {}
}
