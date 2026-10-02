package loupe.db

import std.collection.*
import std.deriving.*
import std.sort.*
import calca.*
import calca.macros.*
import loupe.vfs.*

/**
 * One option `@When` is evaluated against: `os == "Linux"` reads the option `os`.
 */
@Derive[Equatable]
public struct CfgOption {
    public CfgOption(public let key: String, public let value: String) {}
}

/**
 * What `@When` is evaluated against: `os`, `arch`, `backend` and whatever else a build sets, each
 * key once, in the order of the keys.
 */
@Derive[Equatable]
public struct Cfg {
    public let options: Array<CfgOption>

    /**
     * A later option of a key replaces an earlier one.
     */
    public init(options: Array<(String, String)>) {
        let byKey = HashMap<String, String>()
        for ((key, value) in options) {
            byKey[key] = value
        }
        let sorted = byKey.toArray().map {option => CfgOption(option[0], option[1])}
        sort(sorted, by: {a, b => a.key.compare(b.key)})
        this.options = sorted
    }

    /**
     * The value of `key`, `None` if this sets none.
     */
    public func get(key: String): ?String {
        for (option in options where option.key == key) {
            return option.value
        }
        None
    }

    /**
     * These options, with those of `overrides` in place of any of the same key.
     */
    public func overriddenBy(overrides: Cfg): Cfg {
        Cfg(options.map {option => (option.key, option.value)}.concat(overrides.options.map {
            option => (option.key, option.value)
        }))
    }
}

/**
 * A package of a project: the files cjc compiles as one, and how.
 */
@Derive[Equatable]
public struct PackageModel {
    public PackageModel(
        /**
         * As the files name it: `std.collection`, `org::a.b`.
         */
        public let name: String,
        /**
         * Where it is: the directory its name gives, unless the build says otherwise.
         */
        public let dir: VfsPath,
        public let files: Array<VfsPath>,
        /**
         * Compiled with `--no-prelude`: inside it the prelude is the package itself (`std.core`).
         */
        public let noPrelude!: Bool = false,
        /**
         * Whether it is a `macro package`, `None` to read it from its files.
         */
        public let isMacro!: ?Bool = None
    ) {}
}

/**
 * A module of a project: a root on disk and the packages under it, what it may import, and how it
 * is built. A module is its root package to cjc (`protected` stops at the first segment of a
 * package's name); this is the unit of the build, named after its root package.
 */
@Derive[Equatable]
public struct ModuleModel {
    public ModuleModel(
        public let name: String,
        public let root: VfsPath,
        public let packages: Array<PackageModel>,
        /**
         * The modules and binaries it may import, by name; `std` is always there.
         */
        public let deps!: Array<String> = [],
        /**
         * Whether it is the user's: one that is not (a dependency) is analyzed, and reports nothing.
         */
        public let member!: Bool = true,
        /**
         * What `@When` is evaluated against in it, `None` for the project's.
         */
        public let cfg!: ?Cfg = None
    ) {}

    /**
     * How rarely its files change: the user's at every keystroke, a dependency's when it is
     * updated, `std`'s with the SDK.
     */
    public prop durability: Durability {
        get() {
            if (name == "std") {
                Durability.High
            } else if (member) {
                Durability.Low
            } else {
                Durability.Medium
            }
        }
    }
}

/**
 * A package compiled already, a `.cjo` and its library.
 */
@Derive[Equatable]
public struct BinaryPackage {
    public BinaryPackage(public let name: String, public let path: VfsPath) {}
}

/**
 * Modules compiled already, as cjpm's `bin-dependencies` give them: directories every `.cjo` of
 * which is a package (`path-option`), and packages one by one (`package-option`).
 */
@Derive[Equatable]
public struct BinaryModel {
    public BinaryModel(
        public let name: String,
        public let paths: Array<VfsPath>,
        public let packages!: Array<BinaryPackage> = []
    ) {}
}

/**
 * Everything the analysis knows of how the files make a program: the modules and their packages,
 * the binaries they may import, and the cfg. However a project is found, it comes down to this.
 */
@Derive[Equatable]
public struct ProjectModel {
    public ProjectModel(
        public let cfg: Cfg,
        public let modules: Array<ModuleModel>,
        public let binaries!: Array<BinaryModel> = []
    ) {}

    /**
     * The files of every package, each once.
     */
    public func files(): Array<VfsPath> {
        let files = HashSet<VfsPath>()
        let ordered = ArrayList<VfsPath>()
        for (module in modules) {
            for (pkg in module.packages) {
                for (file in pkg.files where files.add(file)) {
                    ordered.add(file)
                }
            }
        }
        ordered.toArray()
    }

    /**
     * The projects as one, with the cfg of the first (`cfg` if there are none). A module of a root
     * seen before adds its packages to that one, a package named as one before it its files: a
     * project opened from two roots has its modules twice. A binary named as one before it is left
     * out.
     */
    public static func merge(projects: Array<ProjectModel>, cfg: Cfg): ProjectModel {
        let modules = ArrayList<ModuleModel>()
        let binaries = ArrayList<BinaryModel>()
        for (project in projects) {
            for (module in project.modules) {
                match (modules.iterator().enumerate().filter {kept => kept[1].root == module.root}.next()) {
                    case Some((index, kept)) => modules[index] = kept.including(module.packages)
                    case None => modules.add(module)
                }
            }
            for (binary in project.binaries where !binaries.iterator().any {kept => kept.name == binary.name}) {
                binaries.add(binary)
            }
        }
        let first = projects.iterator().next().map {project => project.cfg} ?? cfg
        ProjectModel(first, modules.toArray(), binaries: binaries.toArray())
    }
}

extend ModuleModel {
    /**
     * This module with `packages` too: the files of one of a name it has already are added to it.
     */
    func including(packages: Array<PackageModel>): ModuleModel {
        let merged = ArrayList<PackageModel>(this.packages)
        for (pkg in packages) {
            match (merged.iterator().enumerate().filter {kept => kept[1].name == pkg.name}.next()) {
                case Some((index, kept)) =>
                    let files = ArrayList<VfsPath>(kept.files)
                    files.add(all: pkg.files.filter {file => !kept.files.contains(file)})
                    merged[index] = PackageModel(kept.name, kept.dir, files.toArray(), noPrelude: kept.noPrelude,
                        isMacro: kept.isMacro)
                case None => merged.add(pkg)
            }
        }
        ModuleModel(name, root, merged.toArray(), deps: deps, member: member, cfg: cfg)
    }
}

/**
 * The project, as the analysis sees it: at most one per database, set with `High` durability, for
 * it changes only when a manifest does, or a package or a file comes or goes.
 */
@CalcaInput[singleton]
public struct Project {
    public var cfg: Cfg
    public var modules: Array<Module>
    public var binaries: Array<BinaryModel>
}

/**
 * A module of the project, one per root, never dropped: a module gone is no longer in `Project`.
 * Its root, not its name, is what it is: every build script is a module `default` of its own.
 */
@CalcaInput
public struct Module {
    public let root: VfsPath
    public var name: String
    public var packages: Array<Package>
    public var deps: Array<String>
    public var member: Bool
    public var cfg: ?Cfg
}

/**
 * A package of the project, one per name in a module, never dropped: a package gone is no longer
 * in its module. Its files are an input of their own, not found from their texts: a file deleted is an
 * empty text (A5), which nothing tells from an empty file.
 */
@CalcaInput
public struct Package {
    public let name: String
    public var dir: VfsPath
    public var files: Array<FileId>
    public var noPrelude: Bool
    public var isMacro: ?Bool
}

/**
 * The inputs of the project made so far, by name, and what each was last set to; and the
 * durability of each file, its module's. Used on the root handle alone.
 */
class Projects {
    var project: ?(Project, Cfg, Array<Module>, Array<BinaryModel>) = None
    let modules = HashMap<VfsPath, (Module, ModuleModel)>()
    let packages = HashMap<PackageKey, (Package, PackageModel, Durability)>()
    var durabilities = HashMap<FileId, Durability>()
}

/**
 * A package by the root of its module and its name.
 */
@Derive[Hashable, Equatable]
struct PackageKey {
    PackageKey(let root: VfsPath, let name: String) {}
}
