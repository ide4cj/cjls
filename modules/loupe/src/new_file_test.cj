package loupe

import std.env.getTempDirectory
import std.unittest.*
import std.unittest.testmacro.*
import loupe.db.{Cfg, ModuleModel, PackageModel, ProjectModel}
import loupe.vfs.VfsPath
import rope.Rope

@Test
class NewFilePackageLineTest {
    @TestCase
    func macroKindComesFromMetadataOrCurrentHeaders() {
        // arrange
        let root = VfsPath.file(getTempDirectory()).join("app/src")
        let dir = root.join("ms")
        let file = dir.join("a.cj")
        let path = dir.join("new.cj")
        func model(kind!: ?Bool): ProjectModel {
            ProjectModel(
                Cfg([]),
                [ModuleModel("app", root, [PackageModel("app.ms", dir, [file], isMacro: kind)])]
            )
        }
        let macroText = { _: VfsPath => Some(Rope("// header\nmacro package app.ms")) }
        let ordinaryText = { _: VfsPath => Some(Rope("package app.ms")) }

        // act
        let headers =
            [
                newFilePackageLine(model(kind: None), path, macroText),
                newFilePackageLine(model(kind: None), path, ordinaryText),
                newFilePackageLine(model(kind: Some(true)), path, ordinaryText),
                newFilePackageLine(model(kind: Some(false)), path, macroText),
                newFilePackageLine(model(kind: None), dir.join("child").join("new.cj"), macroText),
                newFilePackageLine(model(kind: None), root.join("../../other/new.cj"), macroText)
            ]

        // assert
        @Expect(headers, [Some("macro package app.ms"), Some("package app.ms"), Some("macro package app.ms"),
            Some("package app.ms"), Some("package app.ms.child"), None])
    }
}
