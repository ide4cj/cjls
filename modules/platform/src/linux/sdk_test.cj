features { user.platform.posix, os.linux }
package platform

import std.fs.Path
import std.unittest.*
import std.unittest.testmacro.*

@Test
class SdkToolEnvironmentOnLinuxTest {
    @TestCase
    func putsTheRuntimeFirstOnTheLdLibraryPath() {
        // act
        let fresh = sdkToolEnvironment([("HOME", "/h")], Path("/rt"))
        let added = sdkToolEnvironment([("LD_LIBRARY_PATH", "/old")], Path("/rt"))

        // assert
        @Expect(fresh.get("LD_LIBRARY_PATH"), Some("/rt"))
        @Expect(fresh.get("HOME"), Some("/h"))
        @Expect(added.get("LD_LIBRARY_PATH"), Some("/rt:/old"))
        @Expect(added.get("SDKROOT"), None<String>)
    }
}
