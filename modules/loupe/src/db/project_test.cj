package loupe.db

import std.env.getTempDirectory
import std.sync.*
import std.unittest.*
import std.unittest.testmacro.*
import calca.*
import calca.macros.*
import loupe.vfs.*

let packageFilesRuns = AtomicInt64(0)

/**
 * How many files the package has; it counts its runs.
 */
@CalcaTracked
func packageFileCount(db: AnalysisDatabase, pkg: Package): Int64 {
    packageFilesRuns.fetchAdd(1)
    pkg.files(db).size
}

func at(name: String): VfsPath {
    VfsPath.file(getTempDirectory().join(name))
}

/**
 * A module `app` of a package `app` (`a.cj`, and `b.cj` if `withB`) and a package `app.util`.
 */
func appProject(withB!: Bool = false): ProjectModel {
    let files = if (withB) {
        [at("app/src/a.cj"), at("app/src/b.cj")]
    } else {
        [at("app/src/a.cj")]
    }
    ProjectModel(Cfg([("os", "Linux")]), [
        ModuleModel("app", at("app/src"), [
            PackageModel("app", at("app/src"), files),
            PackageModel("app.util", at("app/src/util"), [at("app/src/util/u.cj")])
        ])
    ])
}

func packageNamed(db: AnalysisDatabase, name: String): Package {
    for (module in db.project().getOrThrow().modules(db)) {
        for (pkg in module.packages(db) where pkg.name(db) == name) {
            return pkg
        }
    }
    throw NoneValueException("no package ${name}")
}

@Test
class ProjectTest {
    @TestCase
    func aProjectSetIsItsModulesAndTheirPackages() {
        // arrange
        let db = AnalysisDatabase()
        let paths = PathInterner()

        // act
        db.setProject(appProject(), paths)

        // assert
        let project = db.project().getOrThrow()
        @Expect(project.cfg(db).get("os"), Some("Linux"))
        @Expect(project.modules(db).map {module => module.name(db)}, ["app"])
        let app = packageNamed(db, "app")
        @Expect(app.files(db), [paths.lookup(at("app/src/a.cj")).getOrThrow()])
        @Expect(packageNamed(db, "app.util").dir(db), at("app/src/util"))
    }

    @TestCase
    func theSameProjectSetAgainChangesNothing() {
        // arrange
        let db = AnalysisDatabase()
        let paths = PathInterner()
        db.setProject(appProject(), paths)
        @Expect(packageFileCount(db, packageNamed(db, "app")), 1)
        let runs = packageFilesRuns.load()

        // act
        db.setProject(appProject(), paths)
        let count = packageFileCount(db, packageNamed(db, "app"))

        // assert
        @Expect(count, 1)
        @Expect(packageFilesRuns.load() - runs, 0)
    }

    @TestCase
    func aFileAddedChangesItsPackageAlone() {
        // arrange
        let db = AnalysisDatabase()
        let paths = PathInterner()
        db.setProject(appProject(), paths)
        let util = packageNamed(db, "app.util")
        @Expect(packageFileCount(db, util), 1)
        let runs = packageFilesRuns.load()

        // act
        db.setProject(appProject(withB: true), paths)
        let utilCount = packageFileCount(db, util)
        let utilRuns = packageFilesRuns.load() - runs
        let appCount = packageFileCount(db, packageNamed(db, "app"))

        // assert - the same inputs, of the same names
        @Expect(packageNamed(db, "app.util"), util)
        @Expect(utilCount, 1)
        @Expect(utilRuns, 0)
        @Expect(appCount, 2)
    }

    @TestCase
    func aModuleIsAsDurableAsItIsRarelyChanged() {
        // arrange
        let root = at("m")

        // act, assert
        @Expect(ModuleModel("app", root, []).durability, Durability.Low)
        @Expect(ModuleModel("dep", root, [], member: false).durability, Durability.Medium)
        @Expect(ModuleModel("std", root, []).durability, Durability.High)
    }

    @TestCase
    func aCfgKeepsTheLastValueOfAKeyInTheOrderOfTheKeys() {
        // act
        let cfg = Cfg([("os", "Linux"), ("arch", "x86_64"), ("os", "macOS")])
        let overridden = cfg.overriddenBy(Cfg([("arch", "aarch64")]))

        // assert
        @Expect(cfg.options.map {option => option.key}, ["arch", "os"])
        @Expect(cfg.get("os"), Some("macOS"))
        @Expect(cfg.get("env"), None<String>)
        @Expect(overridden, Cfg([("os", "macOS"), ("arch", "aarch64")]))
    }

    @TestCase
    func projectsMergedAreOneModulePerRootAndOnePackagePerName() {
        // arrange
        let first = ProjectModel(Cfg([("os", "Linux")]), [ModuleModel("a", at("one"), [PackageModel("a", at("one"), [at("one/x.cj")])])],
            binaries: [BinaryModel("stdx", [at("stdx1")])])
        let second = ProjectModel(Cfg([("os", "Windows")]), [
            ModuleModel("a", at("one"), [PackageModel("a", at("one"), [at("one/y.cj")]), PackageModel("a.b", at("one/b"), [])]),
            ModuleModel("default", at("two"), [PackageModel("default", at("two"), [at("two/build.cj")])])
        ], binaries: [BinaryModel("stdx", [at("stdx2")])])

        // act
        let merged = ProjectModel.merge([first, second], Cfg([]))

        // assert
        @Expect(merged.cfg.get("os"), Some("Linux"))
        @Expect(merged.modules.map {module => module.root}, [at("one"), at("two")])
        @Expect(merged.modules[0].packages.map {pkg => pkg.name}, ["a", "a.b"])
        @Expect(merged.modules[0].packages[0].files, [at("one/x.cj"), at("one/y.cj")])
        @Expect(merged.binaries.map {binary => binary.paths}, [[at("stdx1")]])
    }

    @TestCase
    func modulesOfOneNameAreInputsOfTheirOwnByTheirRoots() {
        // arrange - two build scripts, each a module `default` of its package `default`
        let db = AnalysisDatabase()
        let paths = PathInterner()
        let script = {dir: String => ModuleModel("default", at(dir), [PackageModel("default", at(dir), [at("${dir}/build.cj")])])}

        // act
        db.setProject(ProjectModel(Cfg([]), [script("a"), script("b")]), paths)

        // assert
        let modules = db.project().getOrThrow().modules(db)
        @Expect(modules.size, 2)
        @Expect(modules[0] != modules[1])
        let files = modules.map {module => module.packages(db)[0].files(db)}
        @Expect(files, [[paths.lookup(at("a/build.cj")).getOrThrow()], [paths.lookup(at("b/build.cj")).getOrThrow()]])
    }
}
