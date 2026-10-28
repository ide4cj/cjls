package cjls.macro_host

import std.unittest.*
import std.unittest.testmacro.*
import loupe.db.*
import loupe.vfs.*
import rope.Rope

@Test
class MacroScopeTest {
    @TestCase[scopedFirst in [false, true]]
    func loadedFilesExpandInEachActiveContextAndDropRemovedContexts(scopedFirst: Bool) {
        // arrange
        let db = AnalysisDatabase()
        let paths = PathInterner()
        let root = VfsPath.virtual("/shared")
        let path = VfsPath.virtual("/shared/lib.cj")
        let id = paths.intern(path)
        let primary = db.setFileText(id, Rope("package shared\n"))
        let ordinary = ModuleModel("shared", root, [PackageModel("shared", root, [path])])
        let scoped =
            [
                ModuleModel(
                    "shared",
                    root,
                    [PackageModel("shared", root, [path])],
                    resolutionScope: "first"
                ),
                ModuleModel(
                    "shared",
                    root,
                    [PackageModel("shared", root, [path])],
                    resolutionScope: "second"
                )
            ]
        let ordered =
            if (scopedFirst) { scoped.concat([ordinary]) } else { [ordinary].concat(scoped) }
        db.setProject(ProjectModel(Cfg([]), ordered), paths)
        let modules = db.project().getOrThrow().modules(db)
        let firstPackage =
            modules.filter { module => module.resolutionScope(db) == "first" }[0].packages(db)[0]
        let secondPackage =
            modules.filter { module => module.resolutionScope(db) == "second" }[0].packages(db)[0]
        let first = db.sourceFile(id, context: firstPackage).getOrThrow()
        let second = db.sourceFile(id, context: secondPackage).getOrThrow()

        // act
        let active = macroFiles(db, [id, id, FileId(999)])

        // assert
        @Expect(active, [primary, first, second])
        @Expect(first != second)

        // act
        db.setProject(ProjectModel(Cfg([]), [ordinary]), paths)
        let remaining = macroFiles(db, [id])

        // assert
        @Expect(remaining, [primary])
    }

    @TestCase
    func macroCachesSeparateDependencySelectionsWhileKeepingTheOrdinaryPath() {
        // arrange
        let db = AnalysisDatabase()
        let paths = PathInterner()
        let root = VfsPath.virtual("/shared")
        let pkg = PackageModel("shared", root, [])
        let model =
            ProjectModel(
                Cfg([]),
                [
                    ModuleModel("shared", root, [pkg]),
                    ModuleModel("shared", root, [pkg], resolutionScope: "/app#scripts"),
                    ModuleModel("shared", root, [pkg], resolutionScope: "/other#scripts")
                ]
            )
        db.setProject(model, paths)
        let modules = db.project().getOrThrow().modules(db)

        // act
        let ordinary = macroBuildName(db, modules[0].packages(db)[0], "sdk-version")
        let first = macroBuildName(db, modules[1].packages(db)[0], "sdk-version")
        let second = macroBuildName(db, modules[2].packages(db)[0], "sdk-version")
        db.setProject(model, paths)
        let reloaded = macroBuildName(db, modules[1].packages(db)[0], "sdk-version")

        // assert
        @Expect(ordinary, "sdk-version")
        @Expect(first != ordinary)
        @Expect(second != ordinary)
        @Expect(first != second)
        @Expect(reloaded, first)
        @Expect(!first.contains("/"))
        @Expect(!first.contains("\\"))
    }
}
