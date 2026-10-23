package project_model

import std.collection.ArrayList
import std.env.getTempDirectory
import loupe.vfs.VfsPath
import std.unittest.*
import std.unittest.testmacro.*

@Test
class PathExpansionTest {
    @TestCase
    func homeUsesHomeThenUserProfile() {
        let home = getTempDirectory().join("user name").toString()
        let problems = ArrayList<String>()
        for (key in ["HOME", "USERPROFILE"]) {
            let env: (String) -> ?String =
                {
                    name: String =>
                    if (name == key) {
                        Some(home)
                    } else {
                        None
                    }
                }
            @Expect(expandPath("~", env, problems), home)
            @Expect(expandPath("~/sdk", env, problems), getTempDirectory().join("user name").join("sdk").toString())
        }
        @Expect(expandPath("~other/sdk", {_ => None}, problems), "~other/sdk")
        @Expect(expandPath("dir/~/sdk", {_ => None}, problems), "dir/~/sdk")
        @Expect(problems.size, 0)
    }

    @TestCase
    func valuesAreInsertedOnceAndNamesHaveShellBoundaries() {
        let problems = ArrayList<String>()
        let env: (String) -> ?String =
            {
                name: String =>
                match (name) {
                    case "ROOT" => Some("~/with $LITERAL")
                    case "ROOT_2" => Some("two")
                    case "EMPTY" => Some("")
                    case _ => None
                }
            }
        @Expect(expandPath("$ROOT/\${ROOT_2}/$EMPTY", env, problems), "~/with $LITERAL/two/")
        @Expect(expandPath("\${ROOT}/$ROOT_2", env, problems), "~/with $LITERAL/two")
        @Expect(expandPath("目录/$ROOT_2/файл", env, problems), "目录/two/файл")
        @Expect(expandPath("cost$/$$/$1/\${unfinished", env, problems), "cost$/$$/$1/\${unfinished")
        @Expect(problems.size, 0)
    }

    @TestCase
    func projectPathsUseTheSameExpansionAndKeepRelativePaths() {
        let base = VfsPath.file(getTempDirectory()).join("project")
        let home = VfsPath.file(getTempDirectory()).join("home")
        let loading =
            Loading(
                {
                    name: String =>
                    if (name == "HOME") {
                        Some(home.toString())
                    } else {
                        None
                    }
                },
                hostCfg()
            )
        @Expect(loading.resolve(base, "~/src"), home.join("src"))
        @Expect(loading.resolve(base, "$HOME/src"), home.join("src"))
        @Expect(loading.resolve(base, "\${HOME}/src"), home.join("src"))
        @Expect(loading.resolve(base, "src"), base.join("src"))
        @Expect(loading.problems.size, 0)
    }

    @TestCase
    func missingValuesAreReportedAndPreserved() {
        let problems = ArrayList<String>()
        @Expect(expandPath("~/\${MISSING}/$ABSENT", {_ => None}, problems), "~/\${MISSING}/$ABSENT")
        @Expect(problems.size, 3)
    }
}
