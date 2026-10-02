package loupe.db

import std.collection.HashMap
import std.collection.concurrent.ConcurrentHashMap
import calca.*
import calca.macros.*
import rope.Rope
import loupe.vfs.*

/**
 * One file's text as the analysis sees it. The database keeps one per `FileId`, made the first time
 * the file is set, and never drops it: a file deleted is an empty text (A5).
 */
@CalcaInput
public struct SourceFile {
    public let fileId: FileId
    public var text: Rope
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
    private AnalysisDatabase(private let storage_: Storage, private let files: Files, private let projects: Projects) {}

    public init() {
        this(Storage(), Files(), Projects())
    }

    public prop storage: Storage {
        get() {
            storage_
        }
    }

    /**
     * Its queries are `Cancelled` once `cancelledBy` gives `true`, as well as once the files change.
     */
    public func snapshot(cancelledBy!: () -> Bool = {=> false}): AnalysisDatabase {
        AnalysisDatabase(storage_.snapshot(cancelledBy: cancelledBy), files, projects)
    }

    /**
     * The file's input, `None` for a file never set.
     */
    public func sourceFile(fileId: FileId): ?SourceFile {
        files.get(fileId)
    }

    /**
     * Sets the file's text, in a revision of its own, making its input the first time.
     *
     * @throws IllegalStateException - if this is a snapshot, or a query is running on it
     */
    public func setFileText(fileId: FileId, text: Rope, durability!: Durability = Durability.Low): SourceFile {
        match (files.get(fileId)) {
            case Some(file) =>
                file.setText(this).withDurability(durability).to(text)
                file
            case None =>
                let file = SourceFile(this, fileId, text, durability: durability)
                files.add(fileId, file)
                file
        }
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
                setFileText(change.fileId, vfs.fileContents(change.fileId) ?? Rope(),
                    durability: projects.durabilities.get(change.fileId) ?? Durability.Low)
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
     * Sets the project to `model`, in one revision: a module is the input of its root, a package
     * the input of its name in the module of its root, made the first time, and only what differs
     * from what it was set to last is set again.
     * The files of a module set from now on take its durability; a file is given its id by
     * `paths`. A file set already keeps the durability it has until it changes.
     *
     * @throws IllegalStateException - if this is a snapshot, or a query is running on it
     */
    public func setProject(model: ProjectModel, paths: PathInterner): Unit {
        let durabilities = HashMap<FileId, Durability>()
        batch {
            let modules = model.modules.map {module => setModule(module, paths, durabilities)}
            match (projects.project) {
                case None => projects.project = (Project(this, model.cfg, modules, model.binaries,
                    durability: Durability.High), model.cfg, modules, model.binaries)
                case Some((project, cfg, oldModules, binaries)) =>
                    if (cfg != model.cfg) {
                        project.setCfg(this).withDurability(Durability.High).to(model.cfg)
                    }
                    if (oldModules != modules) {
                        project.setModules(this).withDurability(Durability.High).to(modules)
                    }
                    if (binaries != model.binaries) {
                        project.setBinaries(this).withDurability(Durability.High).to(model.binaries)
                    }
                    projects.project = (project, model.cfg, modules, model.binaries)
            }
        }
        projects.durabilities = durabilities
    }

    private func setModule(model: ModuleModel, paths: PathInterner, durabilities: HashMap<FileId, Durability>): Module {
        let durability = model.durability
        let packages = model.packages.map {
            pkg =>
            let files = pkg.files.map {path => paths.intern(path)}
            for (file in files) {
                durabilities.add(file, durability)
            }
            setPackage(model.root, pkg, files, durability)
        }
        match (projects.modules.get(model.root)) {
            case Some((module, old)) =>
                if (old.name != model.name || old.durability != durability) {
                    module.setName(this).withDurability(durability).to(model.name)
                }
                // a package is the input of its name in this module: the same names are the same inputs
                if (old.packages.map {it => it.name} != model.packages.map {it => it.name} || old.durability != durability) {
                    module.setPackages(this).withDurability(durability).to(packages)
                }
                if (old.deps != model.deps || old.durability != durability) {
                    module.setDeps(this).withDurability(durability).to(model.deps)
                }
                if (old.member != model.member) {
                    module.setMember(this).withDurability(durability).to(model.member)
                }
                if (old.cfg != model.cfg || old.durability != durability) {
                    module.setCfg(this).withDurability(durability).to(model.cfg)
                }
                projects.modules.add(model.root, (module, model))
                module
            case None =>
                let module = Module(this, model.root, model.name, packages, model.deps, model.member, model.cfg,
                    durability: durability)
                projects.modules.add(model.root, (module, model))
                module
        }
    }

    private func setPackage(root: VfsPath, model: PackageModel, files: Array<FileId>, durability: Durability): Package {
        let key = PackageKey(root, model.name)
        match (projects.packages.get(key)) {
            case Some((pkg, old, oldDurability)) =>
                let moved = oldDurability != durability
                if (old.dir != model.dir || moved) {
                    pkg.setDir(this).withDurability(durability).to(model.dir)
                }
                if (old.files != model.files || moved) {
                    pkg.setFiles(this).withDurability(durability).to(files)
                }
                if (old.noPrelude != model.noPrelude || moved) {
                    pkg.setNoPrelude(this).withDurability(durability).to(model.noPrelude)
                }
                if (old.isMacro != model.isMacro || moved) {
                    pkg.setIsMacro(this).withDurability(durability).to(model.isMacro)
                }
                projects.packages.add(key, (pkg, model, durability))
                pkg
            case None =>
                let pkg = Package(this, model.name, model.dir, files, model.noPrelude, model.isMacro,
                    durability: durability)
                projects.packages.add(key, (pkg, model, durability))
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
 * The input of every file, by id, shared by a database and its snapshots.
 */
class Files {
    private let byId = ConcurrentHashMap<FileId, SourceFile>()

    func get(fileId: FileId): ?SourceFile {
        byId.get(fileId)
    }

    func add(fileId: FileId, file: SourceFile): Unit {
        byId.add(fileId, file)
    }
}
