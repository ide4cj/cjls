package loupe

import std.env.getTempDirectory
import std.unittest.*
import std.unittest.testmacro.*
import rope.Rope
import loupe.db.*
import loupe.vfs.VfsPath

@Test
class NewFilePackageLineTest {
    @TestCase
    func macroKindComesFromMetadataOrCurrentHeaders() {
        let root = VfsPath.file(getTempDirectory()).join("app/src")
        let dir = root.join("ms")
        let file = dir.join("a.cj")
        let path = dir.join("new.cj")
        func model(kind: ?Bool): ProjectModel {
            ProjectModel(Cfg([]), [ModuleModel("app", root,
                [PackageModel("app.ms", dir, [file], isMacro: kind)])])
        }
        let macroText = {_: VfsPath => Some(Rope("// header\nmacro package app.ms"))}
        let ordinaryText = {_: VfsPath => Some(Rope("package app.ms"))}
        @Expect(newFilePackageLine(model(None), path, macroText), Some("macro package app.ms"))
        @Expect(newFilePackageLine(model(None), path, ordinaryText), Some("package app.ms"))
        @Expect(newFilePackageLine(model(Some(true)), path, ordinaryText), Some("macro package app.ms"))
        @Expect(newFilePackageLine(model(Some(false)), path, macroText), Some("package app.ms"))
        @Expect(newFilePackageLine(model(None), dir.join("child").join("new.cj"), macroText),
            Some("package app.ms.child"))
        @Expect(newFilePackageLine(model(None), root.join("../../other/new.cj"), macroText), None)
    }
}
