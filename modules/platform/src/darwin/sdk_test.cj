features { user.platform.posix, os.darwin }
package platform

import std.fs.{Path, exists}
import std.unittest.*
import std.unittest.testmacro.*

@Test
class SdkToolEnvironmentOnMacOSTest {
    @TestCase
    func putsTheRuntimeFirstOnTheDyldLibraryPath() {
        // act
        let env = sdkToolEnvironment([("DYLD_LIBRARY_PATH", "/old"), ("SDKROOT", "/sdk")], Path("/rt"))

        // assert
        @Expect(env.get("DYLD_LIBRARY_PATH"), Some("/rt:/old"))
    }

    @TestCase
    func findsTheSdkByXcrunWhereTheVariablesNameNone() {
        // act
        let env = sdkToolEnvironment([], Path("/rt"))

        // assert
        match (env.get("SDKROOT")) {
            case Some(root) => @Expect(exists(Path(root)))
            case None => @Fail("no SDKROOT")
        }
    }

    @TestCase
    func keepsTheSdkTheVariablesName() {
        // act
        let env = sdkToolEnvironment([("SDKROOT", "/sdk")], Path("/rt"))

        // assert
        @Expect(env.get("SDKROOT"), Some("/sdk"))
    }
}
