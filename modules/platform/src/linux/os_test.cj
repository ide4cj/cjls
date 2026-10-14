features { user.platform.posix, os.linux }
package platform

import std.process.executeWithOutput
import std.unittest.*
import std.unittest.testmacro.*

@Test
class HostArchOnLinuxTest {
    /**
     * `struct utsname`'s `machine`, as `uname -m` prints it.
     */
    @TestCase
    func isWhatUnameTellsThisProcess() {
        // act
        let (code, out, _) = executeWithOutput("uname", ["-m"])

        // assert
        @Assert(code, 0)
        @Expect(hostArch(), String.fromUtf8(out).trimAscii())
    }
}
