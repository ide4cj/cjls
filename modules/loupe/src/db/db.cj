package loupe.db

import std.collection.{ArrayList, collectArray, filter, HashMap, HashSet}
import std.collection.concurrent.ConcurrentHashMap
import calca.*
import calca.macros.*
import index_map.IndexMap
import loupe.vfs.*
import py_interop.*
import py_interop.internal_macros.DerivePython
import rope.Rope

/**
 * One file's text as the analysis sees it, and what the macro server answered for its macro calls
 * (#176). The physical editor input is one per `FileId`; independent package contexts have
 * separate source inputs sharing its text. Inputs are never dropped: a deleted file is empty
 * text (A5), and macro outputs belong to the context that produced them.
 */
@DerivePython[opaque]
@CalcaInput
public struct SourceFile {
    public let fileId: FileId
    public var text: Rope
    /**
     * Independent analysis of this physical file in another dependency selection.
     */
    public let context: ?Package = None
    public var macroOutputs: MacroOutputs = MacroOutputs()
}

/**
 * The analysis database: `AnalysisDatabase()` makes one and its root handle, `snapshot` another
 * handle for another thread. See calca's `Storage`.
 *
 * Every query takes this class itself, whatever layer it is in, with no interface of its own in
 * between: calca keeps the state of every query in `storage`, so the class need know none of them,
 * and can sit under all of them.
 */
public class AnalysisDatabase <: Database {
    private AnalysisDatabase(
        private let storage_: Storage,
        private let files: Files,
        private let projects: Projects
    ) {}

    public init() {
        this(Storage(), Files(), Projects())
    }

    public prop storage: Storage {
        get() {
            storage_
        }
    }

    /**
     * Its queries throw `CancelledException` once `cancelledBy` gives `true`, as well as once the
     * files change.
     */
    public func snapshot(cancelledBy!: () -> Bool = { => false }): AnalysisDatabase {
        AnalysisDatabase(storage_.snapshot(cancelledBy: cancelledBy), files, projects)
    }

    /**
     * The ordinary membership's source input when present, otherwise the first active scoped
     * membership; or the explicit package's input for `context`.
     * `None` for a physical file never set; an unscoped context uses the physical input.
     */
    public func sourceFile(fileId: FileId, context!: ?Package = None): ?SourceFile {
        let primary = files.get(fileId) ?? return None
        if (let Some(pkg) <- context) {
            for ((owner, file) in files.contexts(fileId) where owner == pkg) {
                return file
            }
            return primary
        }
        if (let Some(project) <- this.project()) {
            return project.sourceContexts(this).get(fileId) ?? primary
        }
        primary
    }

    /**
     * Sets the physical file's text in every context, making its input the first time.
     * Returns the source identity used by the default editor lookup.
     *
     * @throws IllegalStateException - if this is a snapshot, or a query is running on it
     */
    public func setFileText(
        fileId: FileId,
        text: Rope,
        durability!: Durability = Durability.Low
    ): SourceFile {
        let primary =
            match (files.get(fileId)) {
                case Some(file) =>
                    file.setText(this).withDurability(durability).to(text)
                    file
                case None =>
                    let file = SourceFile(this, fileId, text, durability: durability)
                    files.add(fileId, file)
                    file
            }
        files.rememberText(fileId, text)
        for ((_, file) in files.contexts(fileId)) {
            file.setText(this).withDurability(durability).to(text)
        }
        projects.sourceContexts.get(fileId) ?? primary
    }

    /**
     * Brings the files in step with `changes`, taken from `vfs`, each with its module's durability:
     * `Low` for a file of no module.
     *
     * @throws IllegalStateException - if this is a snapshot, or a query is running on it
     */
    public func applyChanges(vfs: Vfs, changes: Array<ChangedFile>): Unit {
        batch {
            for (change in changes) {
                setFileText(
                    change.fileId,
                    vfs.fileContents(change.fileId) ?? Rope(),
                    durability: projects.durabilities.get(change.fileId) ?? Durability.Low
                )
            }
        }
    }

    /**
     * The project, `None` until one is set.
     */
    public func project(): ?Project {
        Project.tryGet(this)
    }

    /**
     * Sets the project to `model`, in one revision: a module is the input of its root and its
     * name, a package the input of its name in its module, made the first time, and only what differs
     * from what it was set to last is set again.
     * The files of a module set from now on take its durability; a file is given its id by
     * `paths`. A file set already keeps the durability it has until it changes.
     *
     * `binaries` are the packages of `model`'s binaries that were read: a `.cjo` is the input of
     * its binary, package and path, its bytes set only when they differ from the last; one read
     * before and not now holds no bytes. The files of the binaries' sources are given their ids by
     * `paths` too, and the durability of their binary.
     *
     * @throws IllegalStateException - if this is a snapshot, or a query is running on it
     */
    public func setProject(
        model: ProjectModel,
        paths: PathInterner,
        binaries!: Array<CjoFileRead> = []
    ): Unit {
        let durabilities = HashMap<FileId, Durability>()
        let sourceContexts = IndexMap<FileId, SourceFile>()
        let seen = HashSet<FileId>()
        batch {
            let modules =
                model
                    .modules
                    .map { module => setModule(module, paths, durabilities, sourceContexts, seen) }
            let packages = setBinaryPackages(binaries)
            let sources = binarySources(model, paths, durabilities, binaries)
            match (projects.project) {
                case None =>
                    projects.project =
                        (
                            Project(
                                this,
                                model.cfg,
                                modules,
                                model.binaries,
                                packages,
                                sources,
                                durability: Durability.High
                            ),
                            model.cfg,
                            modules,
                            model.binaries,
                            packages,
                            sources
                        )
                case Some((project, cfg, oldModules, oldBinaries, oldPackages, oldSources)) =>
                    if (cfg != model.cfg) {
                        project.setCfg(this).withDurability(Durability.High).to(model.cfg)
                    }
                    if (oldModules != modules) {
                        project.setModules(this).withDurability(Durability.High).to(modules)
                    }
                    if (oldBinaries != model.binaries) {
                        project.setBinaries(this).withDurability(Durability.High).to(model.binaries)
                    }
                    if (oldPackages != packages) {
                        project.setBinaryPackages(this).withDurability(Durability.High).to(packages)
                    }
                    if (oldSources != sources) {
                        project.setBinarySources(this).withDurability(Durability.High).to(sources)
                    }
                    projects.project =
                        (project, model.cfg, modules, model.binaries, packages, sources)
            }
            if (projects.sourceContexts != sourceContexts) {
                let project = projects.project.getOrThrow()[0]
                project.setSourceContexts(this).withDurability(Durability.High).to(sourceContexts)
                projects.sourceContexts = sourceContexts
            }
        }
        projects.durabilities = durabilities
    }

    /**
     * The stamp of the `.cjo` `file` was set with, `None` if it holds no bytes: whether it needs to
     * be read again.
     */
    public func binaryStamp(file: CjoFile): ?FileStamp {
        projects.binaries.get(file).flatMap { binary => binary[1] }
    }

    /**
     * The files of the sources of `model`'s binaries, each named as its binary's `.cjo` names it.
     */
    private func binarySources(
        model: ProjectModel,
        paths: PathInterner,
        durabilities: HashMap<FileId, Durability>,
        reads: Array<CjoFileRead>
    ): Array<BinarySourceFile> {
        let files = ArrayList<BinarySourceFile>()
        for (binary in model.binaries) {
            let durability = binaryDurability(binary.name)
            let sources = binary.sources ?? continue
            for (pkg in sources.packages) {
                let compiled =
                    reads
                        .iterator()
                        .filter {
                            one =>
                            one.file.binary == binary.name && one.file.name == pkg.name
                        }
                        .next()
                        .flatMap { one => projects.binaries.get(one.file).map { kept => kept[0] } }
                let context =
                    compiled
                        .map {
                            one =>
                            setPackage(
                                ModuleKey(sources.dir, binary.name),
                                pkg,
                                pkg.files.map { path => paths.intern(path) },
                                durability,
                                binary: one
                            )
                        }
                for (path in pkg.files) {
                    let fileId = paths.intern(path)
                    durabilities.add(fileId, durability)
                    files
                        .add(
                            BinarySourceFile(
                                binary.name,
                                "${pkg.name}/${path.name}",
                                fileId,
                                context: context
                            )
                        )
                }
            }
        }
        files.toArray()
    }

    private func setBinaryPackages(reads: Array<CjoFileRead>): Array<BinaryPackageFile> {
        let kept = HashSet<CjoFile>()
        let packages = ArrayList<BinaryPackageFile>()
        for (read in reads) {
            let durability = binaryDurability(read.file.binary)
            match ((projects.binaries.get(read.file), read.bytes)) {
                case (Some((pkg, _, old)), Some(bytes)) =>
                    if (bytes != old) {
                        pkg.setBytes(this).withDurability(durability).to(bytes)
                    }
                    projects.binaries.add(read.file, (pkg, read.stamp, bytes))
                    packages.add(pkg)
                case (Some((pkg, Some(_), _)), None) => packages.add(pkg)
                case (None, Some(bytes)) =>
                    let pkg =
                        BinaryPackageFile(
                            this,
                            read.file.binary,
                            read.file.name,
                            read.file.path,
                            bytes,
                            durability: durability
                        )
                    projects.binaries.add(read.file, (pkg, read.stamp, bytes))
                    packages.add(pkg)
                // left unread, but nothing was read before
                case _ => continue
            }
            kept.add(read.file)
        }
        let gone =
            projects.binaries.keys() |> filter { file: CjoFile => !kept.contains(file) } |>
                collectArray
        for (file in gone) {
            let (pkg, stamp, _) = projects.binaries[file]
            if (stamp.isSome()) {
                pkg.setBytes(this).withDurability(binaryDurability(file.binary)).to([])
                projects.binaries.add(file, (pkg, None, []))
            }
        }
        packages.toArray()
    }

    private func setModule(
        model: ModuleModel,
        paths: PathInterner,
        durabilities: HashMap<FileId, Durability>,
        sourceContexts: IndexMap<FileId, SourceFile>,
        seen: HashSet<FileId>
    ): Module {
        let durability = model.durability
        let packages =
            model
                .packages
                .map {
                    pkg =>
                    let files = pkg.files.map { path => paths.intern(path) }
                    for (file in files) {
                        let previous = durabilities.get(file)
                        if (
                            previous.isNone() || durability == Durability.Low ||
                                previous == Some(Durability.High)
                        ) {
                            durabilities.add(file, durability)
                        }
                    }
                    let context = setPackage(model.key, pkg, files, durability)
                    for (fileId in files) {
                        let first = seen.add(fileId)
                        if (!model.resolutionScope.isEmpty()) {
                            let source = ensureSourceContext(fileId, context, durability)
                            if (first) {
                                sourceContexts[fileId] = source
                            }
                        } else {
                            // A script may have reached this path before its ordinary module.
                            sourceContexts.remove(fileId)
                        }
                    }
                    context
                }
        let inactive =
            model
                .inactive
                .map {
                    file =>
                    let fileId = paths.intern(file.path)
                    durabilities.add(fileId, durability)
                    InactiveSourceFile(fileId, file.reason)
                }
        match (projects.modules.get(model.key)) {
            case Some((module, old)) =>
                // a package is the input of its name in this module: the same names are the same inputs
                if (
                    old.packages.map { it => it.name } != model.packages.map { it => it.name } ||
                        old.durability != durability
                ) {
                    module.setPackages(this).withDurability(durability).to(packages)
                }
                if (old.deps != model.deps || old.durability != durability) {
                    module.setDeps(this).withDurability(durability).to(model.deps)
                }
                if (old.testDeps != model.testDeps || old.durability != durability) {
                    module.setTestDeps(this).withDurability(durability).to(model.testDeps)
                }
                if (old.member != model.member) {
                    module.setMember(this).withDurability(durability).to(model.member)
                }
                if (old.cfg != model.cfg || old.durability != durability) {
                    module.setCfg(this).withDurability(durability).to(model.cfg)
                }
                if (old.inactive != model.inactive || old.durability != durability) {
                    module.setInactive(this).withDurability(durability).to(inactive)
                }
                projects.modules.add(model.key, (module, model))
                module
            case None =>
                let module =
                    Module(
                        this,
                        model.root,
                        model.name,
                        model.resolutionScope,
                        packages,
                        model.deps,
                        model.testDeps,
                        model.member,
                        model.cfg,
                        inactive,
                        durability: durability
                    )
                projects.modules.add(model.key, (module, model))
                module
        }
    }

    private func ensureSourceContext(
        fileId: FileId,
        pkg: Package,
        durability: Durability
    ): SourceFile {
        let contexts = files.contexts(fileId)
        for ((owner, source) in contexts where owner == pkg) {
            return source
        }
        let text = files.rememberedText(fileId) ?? Rope()
        let source = SourceFile(this, fileId, text, context: pkg, durability: durability)
        files.addContext(fileId, contexts.concat([(pkg, source)]))
        source
    }

    private func setPackage(
        module: ModuleKey,
        model: PackageModel,
        files: Array<FileId>,
        durability: Durability,
        binary!: ?BinaryPackageFile = None
    ): Package {
        let key = PackageKey(module, model.name)
        let packages =
            if (binary.isSome()) { projects.binarySourcePackages } else { projects.packages }
        match (packages.get(key)) {
            case Some((pkg, old, oldDurability)) =>
                let moved = oldDurability != durability
                if (let Some(one) <- binary && projects.contextBinaries.get(pkg) != binary) {
                    projects.contextBinaries[pkg] = one
                    pkg.setBinary(this).withDurability(durability).to(binary)
                }
                if (old.dir != model.dir || moved) {
                    pkg.setDir(this).withDurability(durability).to(model.dir)
                }
                if (old.files != model.files || moved) {
                    pkg.setFiles(this).withDurability(durability).to(files)
                    pkg.setFilePaths(this).withDurability(durability).to(model.files)
                }
                let testsChanged =
                    old.files.filter { file => isTestFile(file) } !=
                        model.files.filter { file => isTestFile(file) }
                if (testsChanged || moved) {
                    pkg.setTestFiles(this).withDurability(durability).to(testFilesOf(model, files))
                }
                if (old.noPrelude != model.noPrelude || moved) {
                    pkg.setNoPrelude(this).withDurability(durability).to(model.noPrelude)
                }
                if (old.isMacro != model.isMacro || moved) {
                    pkg.setIsMacro(this).withDurability(durability).to(model.isMacro)
                }
                if (old.cfg != model.cfg || moved) {
                    pkg.setCfg(this).withDurability(durability).to(model.cfg)
                }
                packages.add(key, (pkg, model, durability))
                pkg
            case None =>
                let pkg =
                    Package(
                        this,
                        model.name,
                        model.dir,
                        files,
                        model.files,
                        model.noPrelude,
                        model.isMacro,
                        model.cfg,
                        testFiles: testFilesOf(model, files),
                        binary: binary,
                        durability: durability
                    )
                packages.add(key, (pkg, model, durability))
                if (let Some(one) <- binary) {
                    projects.contextBinaries[pkg] = one
                }
                pkg
        }
    }

    /**
     * Makes every change `change` makes to the files one revision: the snapshots are cancelled
     * once, and what is in flight waited for once. Nothing is read inside it.
     *
     * @throws IllegalStateException - if this is a snapshot, or a query is running on it, or
     * `change` reads
     */
    public func batch<T>(change: () -> T): T {
        storage_.batch(change)
    }
}

/**
 * Those of `files`, the ids of `model`'s files, that are its tests: named `*_test.cj`, which cjc compiles of a
 * package only under `--test` (D129).
 */
func testFilesOf(model: PackageModel, files: Array<FileId>): Array<FileId> {
    let found = ArrayList<FileId>()
    for (i in 0..model.files.size where isTestFile(model.files[i])) {
        found.add(files[i])
    }
    found.toArray()
}

/**
 * Whether the file at `path` is a test, by its name.
 */
func isTestFile(path: VfsPath): Bool {
    path.name.endsWith("_test.cj")
}

/**
 * The input of every file, by id, shared by a database and its snapshots.
 */
class Files {
    private let byId = ConcurrentHashMap<FileId, SourceFile>()
    private let contextual = ConcurrentHashMap<FileId, Array<(Package, SourceFile)>>()
    /**
     * Root writes retain the physical text so creating a context needs no input read inside
     * setProject's batch. Rope shares its storage with the source input.
     */
    private let physicalTexts = HashMap<FileId, Rope>()

    func rememberText(fileId: FileId, text: Rope): Unit {
        physicalTexts[fileId] = text
    }

    func rememberedText(fileId: FileId): ?Rope {
        physicalTexts.get(fileId)
    }

    func contexts(fileId: FileId): Array<(Package, SourceFile)> {
        contextual.get(fileId) ?? []
    }

    func addContext(fileId: FileId, contexts: Array<(Package, SourceFile)>): Unit {
        contextual.add(fileId, contexts)
    }

    func get(fileId: FileId): ?SourceFile {
        byId.get(fileId)
    }

    func add(fileId: FileId, file: SourceFile): Unit {
        byId.add(fileId, file)
    }
}
