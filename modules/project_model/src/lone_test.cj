package project_model

import std.env.{getTempDirectory, getVariable}
import std.unittest.*
import std.unittest.testmacro.*
import loupe.db.*
import loupe.vfs.VfsPath

@Test
class LoneFileProjectsTest {
    @TestCase
    func aFileOfNoPackageIsAModuleOfItsOwnRootedAtItAndNamedByItsPackageLineWithStdAlone() {
        // arrange - a file of the project, a file of none with a `package` line and one without, and no Cangjie file
        let dir = VfsPath.file(getTempDirectory()).join("lone")
        let covered = dir.join("src/a.cj")
        let model =
            ProjectModel(
                LINUX,
                [ModuleModel("a", dir, [PackageModel("a", dir.join("src"), [covered])])]
            )
        let script = dir.join("scripts/x.cj")
        let files =
            [
                (script, Some("tools.x")),
                (dir.join("y.cj"), None<String>),
                (covered, Some("a")),
                (dir.join("notes.txt"), None<String>)
            ]

        // act
        let loads = loneFileProjects(model, files, env: { name => getVariable(name) }, cfg: LINUX)

        // assert
        @Expect(loads.map {load => load.source.toString()}, ["a file alone at ${script}", "a file alone at ${dir.join("y.cj")}"])
        @Expect(loads.map {load => packagesOf(load.model, dir)}, [["tools: tools.x=scripts/x.cj"], ["default: default=y.cj"]])
        @Expect(loads.map {load => load.model.modules[0].root}, [script, dir.join("y.cj")])
        @Expect(loads.iterator().all {load => load.model.modules[0].deps.isEmpty()})
        @Expect(loads.map {load => load.model.binaries.map {binary => binary.name}}, [["std"], ["std"]])
    }

    @TestCase
    func aFileTheBuildLeavesOutOrOfABinarysSourcesIsNoneAlone() {
        // arrange
        let dir = VfsPath.file(getTempDirectory()).join("lone")
        let inactive = dir.join("src/ohos/a.cj")
        let source = dir.join("std/core/b.cj")
        let model =
            ProjectModel(
                LINUX,
                [ModuleModel("a", dir, [], inactive: [InactiveFile(inactive, "left out")])],
                binaries: [
                    BinaryModel(
                        "std",
                        [],
                        sources: BinarySources(
                            dir.join("std"),
                            [PackageModel("std.core", dir.join("std/core"), [source])]
                        )
                    )
                ]
            )

        // act
        let loads =
            loneFileProjects(
                model,
                [(inactive, None), (source, Some("std.core"))],
                env: noEnv,
                cfg: LINUX
            )

        // assert
        @Expect(loads.size, 0)
    }
}
