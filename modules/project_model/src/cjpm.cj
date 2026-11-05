package project_model

import std.collection.*
import std.fs.*
import std.sort.*
import ftoml.*
import loupe.db.*
import loupe.vfs.{VfsPath, cjoFilesIn}

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
 * downloaded sources are reported in the problems. `buildMode` selects release by default,
 * or debug as `cjpm build -g`, independently of the target conditions in `cfg`.
 * Script dependency source and binary tables use the host target throughout their graph.
 * `enabledFeatures` adds explicit CJMP features; `deduceFeatures` controls implicit target OS
 * features. Both correspond to cjpm's CLI inputs and affect the ordinary/test graph only.
 * `includeTestFeatures` selects the feature graph of `cjpm test` rather than `cjpm build`;
 * discovered test modules remain available in either configuration.
 *
 * @throws ProjectException - if the file cannot be read
 */
public func loadCjpmProject(
    file: VfsPath,
    env!: (String) -> ?String,
    cfg!: Cfg = hostCfg(),
    buildMode!: BuildMode = Release,
    enabledFeatures!: Array<String> = [],
    deduceFeatures!: Bool = true,
    includeTestFeatures!: Bool = false
): ?ProjectLoad {
    let path = file.filePath ?? return None
    if (!isFile(path)) {
        return None
    }
    let loading = Loading(env, cfg)
    let manifest = readManifest(file)
    let dir = file.parent.getOrThrow()
    let lowering = CjpmLowering(
        loading,
        dir,
        manifest,
        buildMode,
        enabledFeatures,
        deduceFeatures,
        includeTestFeatures
    )
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
    let ordered = modules
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
    private let featureManifests = HashMap<CjpmDirectory, Manifest>()
    private let propagatedFeatures = HashMap<CjpmDirectory, HashSet<String>>()
    private let scripts = HashSet<VfsPath>()
    private let invalidReplacements = HashSet<String>()
    private let git: CjpmGit
    private let registry: CjpmRegistry

    CjpmLowering(
        private let loading: Loading,
        private let root: VfsPath,
        private let manifest: Manifest,
        private let buildMode: BuildMode,
        private let configuredFeatures: Array<String>,
        private let deduceFeatures: Bool,
        private let includeTestFeatures: Bool
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
            discover(member, script: false)
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
                !selected.contains(CjpmSelection(name, isScript: script)) ||
                    registrySelected.contains(CjpmSelection(name, isScript: script))
            ) {
                selectDependency(name, dep, base, script: script, registry: true)
            }
        }
        propagateFeatures()
    }

    /**
     * cjpm validates replacement versions even when no dependency reaches them.
     */
    private func validateReplacements(): Unit {
        for ((name, dep) in manifest.replace ?? HashMap<String, Dependency>()) {
            let version: ?String =
                match (dep) {
                    case Version(text) => Some(text)
                    case Table(table) where table.path.isNone() && table.git.isNone() =>
                        table.version
                    case _ => None
                }
            if (let Some(text) <- version) {
                if (!isExactRegistryVersion(text)) {
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

    private func discover(dir: VfsPath, script!: Bool): Unit {
        if (!discovered.add(CjpmDirectory(dir, isScript: script))) {
            return
        }
        try {
            let manifest =
                if (dir == root) { this.manifest } else { readManifest(dir.join("cjpm.toml")) }
            featureManifests[CjpmDirectory(dir, isScript: script)] = manifest
            if (let Some(pkg) <- manifest.pkg) {
                let name = packageName(pkg)
                let key = CjpmSelection(name, isScript: script)
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
            let deps = dependencies(manifest, dir, forScript: script)
            let tests: Array<(String, Dependency, VfsPath)> =
                if (script) { [] } else { dependencies(manifest, dir, tests: true) }
            for ((name, dep, base) in deps.concat(tests)) {
                selectDependency(name, dep, base, script: script)
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
        for ((name, dep, base) in dependencies(manifest, dir, script: true)) {
            selectDependency(name, dep, base, script: true)
        }
    }

    private func selectDependency(
        name: String,
        declared: Dependency,
        base: VfsPath,
        script!: Bool,
        registry!: Bool = false
    ): Unit {
        if (!script && invalidReplacements.contains(name)) {
            return
        }
        let replacement: ?Dependency =
            if (script) { None } else { manifest.replace.flatMap { all => all.get(name) } }
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
        let key = CjpmSelection(name, isScript: script)
        if (!canSelectDependency(key, path, local: local)) {
            return
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
        discover(path, script: script)
    }

    /**
     * Keeps an existing local selection; registry requirements may yield to a local source.
     */
    private func canSelectDependency(key: CjpmSelection, path: VfsPath, local!: Bool): Bool {
        let previous = selected.get(key) ?? return true
        if (previous == path) {
            return false
        }
        if (registrySelected.contains(key)) {
            return true
        }
        if (local) {
            let scope = if (key.isScript) { "build-script" } else { "ordinary/test" }
            let remedy =
                if (key.isScript) {
                    "Align script dependency declarations"
                } else {
                    "Use entry [replace] to select one source"
                }
            loading
                .problems
                .add(
                    "Conflicting ${scope} dependency `${key.name}`: ${previous} and ${path}; keeping ${previous}. ${remedy}, then run `cjpm update`."
                )
        }
        false
    }

    /**
     * Resolve features after source selection and before lowering: later consumers can enable
     * an already discovered dependency. Each user feature requests its named owner only.
     */
    private func propagateFeatures(): Unit {
        let entries =
            featureManifests
                .toArray()
                .filter {
                    entry =>
                    let (key, manifest) = entry
                    let pkg = manifest.pkg ?? return false
                    selected.get(CjpmSelection(packageName(pkg), isScript: key.isScript)) ==
                        Some(key.dir)
                }
        sort(
            entries,
            by: { a, b => "${a[0].dir}:${a[0].isScript}".compare("${b[0].dir}:${b[0].isScript}") }
        )
        let active = activeFeatureModules()
        let owners = HashMap<CjpmSelection, CjpmDirectory>()
        for ((key, manifest) in entries) {
            let pkg = manifest.pkg.getOrThrow()
            if (active.contains(key)) {
                owners[CjpmSelection(pkg.name, isScript: key.isScript)] = key
            }
            propagatedFeatures[key] = HashSet<String>(moduleFeatures(key, manifest, []))
        }
        let participating = entries.filter { entry => active.contains(entry[0]) }
        validateFeatures(participating, owners)
        closeFeatures(participating, owners, active)
    }

    /**
     * Test modules stay discovered for editor imports, but only the selected command's roots
     * contribute feature requests. Build-script dependencies use their independent graph.
     */
    private func activeFeatureModules(): HashSet<CjpmDirectory> {
        let active = HashSet<CjpmDirectory>()
        let pending = ArrayList<CjpmDirectory>(
            members.map { dir => CjpmDirectory(dir, isScript: false) }
        )
        addScriptFeatureRoots(root, manifest, pending)
        var index = 0
        while (index < pending.size) {
            let key = pending[index]
            index++
            if (!active.add(key)) {
                continue
            }
            let manifest = featureManifests.get(key) ?? continue
            let ordinary = dependencies(manifest, key.dir, forScript: key.isScript)
            let tests: Array<(String, Dependency, VfsPath)> =
                if (includeTestFeatures && !key.isScript) {
                    dependencies(manifest, key.dir, tests: true)
                } else {
                    []
                }
            for ((name, _, _) in ordinary.concat(tests)) {
                if (let Some(dir) <- selected.get(CjpmSelection(name, isScript: key.isScript))) {
                    pending.add(CjpmDirectory(dir, isScript: key.isScript))
                }
            }
            addScriptFeatureRoots(key.dir, manifest, pending)
        }
        active
    }

    private func addScriptFeatureRoots(
        dir: VfsPath,
        manifest: Manifest,
        pending: ArrayList<CjpmDirectory>
    ): Unit {
        if (!(dir.join(BUILD_SCRIPT).filePath.map { path => isFile(path) } ?? false)) {
            return
        }
        for ((name, _, _) in dependencies(manifest, dir, script: true)) {
            if (let Some(path) <- selected.get(CjpmSelection(name, isScript: true))) {
                pending.add(CjpmDirectory(path, isScript: true))
            }
        }
    }

    /**
     * cjpm starts a fresh script configuration, without the entry CLI's flags or deduction
     * switch. Invalid foreign-owner mapping declarations cannot enable other modules.
     */
    private func moduleFeatures(
        key: CjpmDirectory,
        manifest: Manifest,
        incoming: Array<String>
    ): Array<String> {
        let explicit: Array<String> = if (key.isScript) { [] } else { configuredFeatures }
        let pkg = manifest.pkg.getOrThrow()
        let mappings =
            (manifest.featureTables ?? [])
                .filter {
                    feature =>
                    feature
                        .name
                        .flatMap { name => normalizedFeature(name) }
                        .map {
                            name =>
                            featureOwner(name).map { owner => owner == pkg.name } ?? true
                        } ??
                        false
                }
        enabledFeatures(
            mappings,
            graphCfg(forScript: key.isScript),
            always: (pkg.alwaysEnabledFeatures ?? []).concat(explicit).concat(incoming),
            deduce: key.isScript || deduceFeatures
        )
    }

    private func closeFeatures(
        entries: Array<(CjpmDirectory, Manifest)>,
        owners: HashMap<CjpmSelection, CjpmDirectory>,
        active: HashSet<CjpmDirectory>
    ): Unit {
        var changed = true
        while (changed) {
            changed = false
            for ((key, manifest) in entries) {
                let enabled = moduleFeatures(key, manifest, propagatedFeatures[key].toArray())
                propagatedFeatures[key].add(all: enabled)
                for (feature in enabled) {
                    let owner =
                        featureOwner(feature)
                            .flatMap {
                                name =>
                                owners.get(CjpmSelection(name, isScript: key.isScript))
                            } ??
                            continue
                    if (active.contains(owner) && propagatedFeatures[owner].add(feature)) {
                        changed = true
                    }
                }
            }
        }
    }

    private func validateFeatures(
        entries: Array<(CjpmDirectory, Manifest)>,
        owners: HashMap<CjpmSelection, CjpmDirectory>
    ): Unit {
        let reported = HashSet<String>()
        for (text in configuredFeatures) {
            reportFeatureProblem(featureReferenceProblem(text, false, owners), reported)
        }
        for ((key, manifest) in entries) {
            let references = ArrayList<String>(
                manifest.pkg.getOrThrow().alwaysEnabledFeatures ?? []
            )
            for (feature in manifest.featureTables ?? []) {
                for (name in feature.declaredNames) {
                    reportFeatureProblem(featureDeclarationProblem(name, manifest), reported)
                }
                // `names` declares independent flags and ignores a sibling mapping in cjpm.
                if (feature.name.isSome()) {
                    references.add(all: feature.mapping ?? [])
                }
            }
            for (set in manifest.sourceSets ?? []) {
                references.add(all: set.featureNames ?? [])
            }
            for (text in references) {
                reportFeatureProblem(featureReferenceProblem(text, key.isScript, owners), reported)
            }
        }
    }

    private func featureDeclarationProblem(text: String, manifest: Manifest): String {
        let normalized = normalizedFeature(text) ?? return invalidFeatureProblem(text)
        if (
            let Some(owner) <- featureOwner(normalized) && owner != manifest.pkg.getOrThrow().name
        ) {
            return "Feature declaration `${normalized}` must belong to `user.${manifest.pkg.getOrThrow().name}.`."
        }
        ""
    }

    private func featureReferenceProblem(
        text: String,
        script: Bool,
        owners: HashMap<CjpmSelection, CjpmDirectory>
    ): String {
        let value = normalizedFeature(text) ?? return invalidFeatureProblem(text)
        let owner = featureOwner(value) ?? return ""
        let directory = owners.get(CjpmSelection(owner, isScript: script)) ?? return ""
        let declared = featureManifests[directory].featureTables ?? []
        if (declared
            .iterator()
            .any {
                feature =>
                feature
                    .declaredNames
                    .iterator()
                    .any { name => normalizedFeature(name) == Some(value) }
            }) {
            ""
        } else {
            "Feature `${value}` is not declared by dependency `${owner}`."
        }
    }

    private func reportFeatureProblem(problem: String, reported: HashSet<String>): Unit {
        if (!problem.isEmpty() && reported.add(problem)) {
            loading.problems.add(problem)
        }
    }

    /**
     * The name of the module in `dir`, lowered the first time; `None` if it has no manifest, or
     * no package.
     */
    func module(dir: VfsPath, forScript!: Bool = false): ?String {
        let key = CjpmDirectory(dir, isScript: forScript)
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
        if (
            let Some(chosen) <- selected.get(CjpmSelection(name, isScript: forScript)) &&
                chosen != dir
        ) {
            let result = module(chosen, forScript: forScript)
            reached.add(key, result)
            return result
        }
        reached.add(key, name)
        let deps = ArrayList<String>()
        let testDeps = ArrayList<String>()
        let ordinary = dependencies(manifest, dir, forScript: forScript)
        let tests: Array<(String, Dependency, VfsPath)> =
            if (forScript) { [] } else { dependencies(manifest, dir, tests: true) }
        let normalNames = ordinary.map { entry => entry[0] }
        for ((key, _, _) in ordinary.concat(tests)) {
            if (let Some(path) <- selected.get(CjpmSelection(key, isScript: forScript))) {
                if (let Some(name) <- module(path, forScript: forScript)) {
                    if (normalNames.contains(key)) {
                        if (!deps.contains(name)) {
                            deps.add(name)
                        }
                    } else if (!testDeps.contains(name)) {
                        testDeps.add(name)
                    }
                }
            }
        }
        let member = !forScript && members.contains(dir)
        if (member) {
            deps.add(all: workspaceBinaries)
        }
        deps.add(all: binaryDeps(manifest, dir, forScript: forScript))
        let unique = ArrayList<String>()
        for (dep in deps where !unique.contains(dep)) {
            unique.add(dep)
        }
        // under `src-dir = "."` the build script is beside the sources, and cjpm leaves it out of them
        let script = dir.join(BUILD_SCRIPT)
        let (sources, found, inactive) = sourcesOf(
            name,
            dir,
            manifest,
            pkg,
            propagatedFeatures.get(key).map { all => all.toArray() } ?? []
        )
        let packages = ArrayList<PackageModel>()
        for (pkg in found) {
            let files = pkg.files.filter { file => file != script }
            if (!files.isEmpty()) {
                packages.add(
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
        modules.add(
            ModuleModel(
                name,
                sources,
                packages.toArray(),
                deps: unique.toArray(),
                testDeps: testDeps.toArray(),
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
        pkg: ManifestPackage,
        enabled: Array<String>
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
        let picked = sourceSetChain(sets, [], loading.cfg, always: enabled, deduce: false)
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
        for ((key, _, _) in dependencies(manifest, dir, script: true)) {
            if (let Some(path) <- selected.get(CjpmSelection(key, isScript: true))) {
                if (let Some(name) <- module(path, forScript: true)) {
                    if (!deps.contains(name)) {
                        deps.add(name)
                    }
                }
            }
        }
        modules.add(
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
     * Declarations retain their manifest directory: inherited paths belong to the workspace.
     * Keep duplicate names until source selection so conflicts are reported rather than hidden
     * by a target or member table. Source and script graphs share cjpm's source precedence.
     * `script` selects declarations of a build script; `forScript` selects the host tables of
     * a module compiled for that script, whose dependencies remain ordinary declarations.
     */
    private func dependencies(
        manifest: Manifest,
        dir: VfsPath,
        tests!: Bool = false,
        script!: Bool = false,
        forScript!: Bool = false
    ): Array<(String, Dependency, VfsPath)> {
        let all = ArrayList<(String, Dependency, VfsPath)>()
        let declarations = ArrayList<(Manifest, VfsPath)>([(manifest, dir)])
        if (this.manifest.workspace.isSome() && dir != root && members.contains(dir)) {
            declarations.add((this.manifest, root))
        }
        for ((declared, base) in declarations) {
            let target = targetOf(declared, forScript: forScript)
            let mode = target.flatMap { it => modeOf(it) }
            let tables =
                if (script) {
                    [declared.scriptDependencies]
                } else if (tests) {
                    [
                        declared.testDependencies,
                        target.flatMap { it => it.testDependencies },
                        mode.flatMap { it => it.testDependencies }
                    ]
                } else {
                    [
                        declared.dependencies,
                        target.flatMap { it => it.dependencies },
                        mode.flatMap { it => it.dependencies }
                    ]
                }
            for (table in tables) {
                let sorted = (table ?? HashMap<String, Dependency>()).toArray()
                sort(sorted, by: { a, b => a[0].compare(b[0]) })
                all.add(all: sorted.map { entry => (entry[0], entry[1], base) })
            }
        }
        let sorted = all.toArray()
        sort(sorted, by: { a, b => a[0].compare(b[0]) }, stable: true)
        sorted
    }

    /**
     * The names of the binaries `manifest` names for the target, each added to the project the
     * first time: one per directory of `path-option`, named as the directory is, and one per
     * module of `package-option`.
     */
    private func binaryDeps(
        manifest: Manifest,
        dir: VfsPath,
        forScript!: Bool = false
    ): Array<String> {
        let target = targetOf(manifest, forScript: forScript) ?? return []
        if (let Some(mode) <- modeOf(target).flatMap { it => it.binDependencies }) {
            return modeBinaryDeps(mode, target.binDependencies, dir, forScript: forScript)
        }
        let bin = target.binDependencies ?? return []
        let names = ArrayList<String>()
        for (option in bin.pathOption ?? []) {
            let path = loading.resolve(dir, option)
            names.add(addBinary(BinaryModel(path.name, [path]), forScript: forScript))
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
            names.add(addBinary(BinaryModel(module, [], packages: packages), forScript: forScript))
        }
        names.toArray()
    }

    /**
     * cjpm selects packages, not entire directories: a mode directory may replace one common
     * package while retaining another. Materialize the selected packages before lowering so
     * mode path-option also beats common package-option, without adding profiles to the JSON model.
     */
    private func modeBinaryDeps(
        mode: BinDependencies,
        common: ?BinDependencies,
        dir: VfsPath,
        forScript!: Bool
    ): Array<String> {
        let selected = HashMap<String, BinaryPackage>()
        let paths = ArrayList<VfsPath>()
        for (bin in [mode, common ?? BinDependencies()]) {
            for ((name, path) in bin.packageOption ?? HashMap<String, String>()) {
                if (!selected.contains(name)) {
                    selected[name] = BinaryPackage(name, loading.resolve(dir, path))
                }
            }
            for (option in bin.pathOption ?? []) {
                let path = loading.resolve(dir, option)
                if (!paths.contains(path)) {
                    paths.add(path)
                }
                for (file in cjoFilesIn(path.name, path)) {
                    if (!selected.contains(file.name)) {
                        selected[file.name] = BinaryPackage(file.name, file.path)
                    }
                }
            }
        }
        let names = selected.keys().toArray().map { name => moduleOf(name) }
        // Even an empty search directory must remain watched for newly built packages.
        let moduleNames =
            if (names.isEmpty()) { paths.toArray().map { path => path.name } } else { names }
        let modules = HashSet<String>(moduleNames).toArray()
        sort(modules)
        let owners = ArrayList<String>()
        for (name in modules) {
            let packages = selected.values().toArray().filter { pkg => moduleOf(pkg.name) == name }
            sort(packages, by: { a, b => a.name.compare(b.name) })
            owners.add(
                addBinary(
                    BinaryModel(name, paths.toArray(), packages: packages, discoverPackages: false),
                    forScript: forScript
                )
            )
        }
        owners.toArray()
    }

    private func modeOf(target: Target): ?TargetMode {
        match (buildMode) {
            case Debug => target.debug
            case Release => target.release
        }
    }

    /**
     * Binary owners identify imports independently of package names. Keep host artifacts out of
     * an ordinary owner's first-selection cache even when both graphs import the same package.
     */
    private func addBinary(binary: BinaryModel, forScript!: Bool): String {
        let name = if (forScript) { "${scriptScope}:${binary.name}" } else { binary.name }
        if (!binaries.iterator().any { kept => kept.name == name }) {
            binaries.add(
                BinaryModel(
                    name,
                    binary.paths,
                    packages: binary.packages,
                    discoverPackages: binary.discoverPackages,
                    sources: binary.sources
                )
            )
        }
        name
    }

    private prop scriptScope: String {
        get() {
            "${root}#scripts"
        }
    }

    private func graphCfg(forScript!: Bool): Cfg {
        if (forScript) { hostCfg() } else { loading.cfg }
    }

    private func targetOf(manifest: Manifest, forScript!: Bool): ?Target {
        let triple = cjpmTriple(graphCfg(forScript: forScript)) ?? return None
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
 * Whether a replacement selects one valid registry version, rather than a requirement range.
 */
private func isExactRegistryVersion(text: String): Bool {
    try {
        registryVersion(text)
        true
    } catch (_: ProjectException) {
        false
    } catch (_: IllegalArgumentException) {
        false
    }
}
