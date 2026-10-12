package project_model

import std.collection.*
import std.unittest.*
import std.unittest.testmacro.*
import loupe.db.*

@Test
class CfgTomlTest {
    @TestCase
    func aCfgTomlInAPackagesDirectoryIsItsCfg() {
        // arrange
        let dir = tree([("src/main.cj", ""), ("src/cfg.toml", "feature = \"fast\"\nlevel = \"2\"\n"), ("src/sub/a.cj", "")])
        let model = ProjectModel(Cfg([]), [ModuleModel("m", dir, packagesUnder("m", dir.join("src")))])
        let problems = ArrayList<String>()

        // act
        let read = withPackageCfgs(model, problems)
        removeTree(dir)

        // assert - `cfg.toml` is of the package whose directory holds it, not of those under it
        let packages = read.modules[0].packages
        @Expect(packages[0].cfg == Some(Cfg([("feature", "fast"), ("level", "2")])))
        @Expect(packages[1].cfg.isNone())
        @Expect(problems.size, 0)
    }

    @TestCase
    func aCfgTomlNotOfStringsIsAProblemAndLeftOut() {
        // arrange
        let dir = tree([("main.cj", ""), ("cfg.toml", "level = 2\n")])
        let model = ProjectModel(Cfg([]), [ModuleModel("m", dir, packagesUnder("m", dir))])
        let problems = ArrayList<String>()

        // act
        let read = withPackageCfgs(model, problems)
        removeTree(dir)

        // assert
        @Expect(read.modules[0].packages[0].cfg.isNone())
        @Expect(problems.size, 1)
    }

    @TestCase
    func theHostSetsTestAndAnEnvironment() {
        // act
        let cfg = hostCfg()

        // assert
        @Expect(cfg.get("test"), Some("true"))
        @Expect(cfg.get("env").isSome())
    }
}
