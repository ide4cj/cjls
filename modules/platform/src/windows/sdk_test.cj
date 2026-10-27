features {os.windows}
package platform

import std.fs.Path
import std.unittest.*
import std.unittest.testmacro.*

@Test
class SdkToolEnvironmentOnWindowsTest {
    @TestCase
    func putsTheRuntimeFirstOnPathWhateverItsCase() {
        // act
        let env = sdkToolEnvironment([("Path", "C:\\old"), ("TEMP", "C:\\t")], Path("C:\\rt"))

        // assert
        @Expect(env.get("PATH"), Some("C:\\rt;C:\\old"))
        @Expect(env.contains("Path"), false)
        @Expect(env.get("TEMP"), Some("C:\\t"))
    }
}
