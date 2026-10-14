features { user.platform.posix, os.darwin }
package platform

import std.process.executeWithOutput
import std.unittest.*
import std.unittest.testmacro.*

@Test
class HostArchOnMacOSTest {
    /**
     * `struct utsname`'s `machine`, as `uname -m` prints it, `arm64` named as cjc does.
     */
    @TestCase
    func isWhatUnameTellsThisProcess() {
        // act
        let (code, out, _) = executeWithOutput("uname", ["-m"])

        // assert
        @Assert(code, 0)
        @Expect(String.fromUtf8(out).trimAscii(), "arm64")
        @Expect(hostArch(), "aarch64")
    }
}
