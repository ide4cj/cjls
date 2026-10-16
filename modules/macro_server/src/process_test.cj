package macro_server

import std.fs.Path
import std.unittest.*
import std.unittest.testmacro.*
import platform.ChildPipes

@Test
class MacroServerArgsTest {
    @TestCase
    func theServerGetsItsTwoPipeEndsSerialAndCjc(): Unit {
        // arrange
        let paths = MacroServerPaths.inSdk(Path("C:\\Cangjie SDK"), "windows_x86_64_cjnative")

        // act
        let args = macroServerArgs(paths, ChildPipes(read: "520", write: "524", parent: None))

        // assert
        @Expect(args, ["520", "524", "0", paths.cjc.toString()])
        @Expect(paths.server.toString().endsWith("LSPMacroServer.exe"))
    }

    @TestCase
    func aParentToWatchGoesLast(): Unit {
        // arrange
        let paths = MacroServerPaths.inSdk(Path("/sdk"), "linux_x86_64_cjnative")

        // act
        let args = macroServerArgs(paths, ChildPipes(read: "3", write: "4", parent: 42))

        // assert
        @Expect(args, ["3", "4", "0", paths.cjc.toString(), "42"])
    }

    @TestCase
    func theServerLoadsTheRuntimeThenItsOwnLibrariesBeforeAnyInherited(): Unit {
        // arrange
        let sdk = Path("/sdk")
        let paths = MacroServerPaths.inSdk(sdk, "linux_x86_64_cjnative")

        // act
        let dirs = macroServerLibraryDirs(paths)

        // assert: as envsetup orders them, the second what the server's RUNPATH names ($ORIGIN/../lib); spelled
        // as the host joins paths (`\` on Windows)
        @Expect(dirs.map {dir => dir.toString()},
            [paths.runtimeLib.toString(), sdk.join("tools").join("lib").toString()])
    }
}
