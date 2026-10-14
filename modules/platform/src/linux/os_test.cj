features { user.platform.posix, os.linux }
package platform

import std.process.executeWithOutput
import std.unittest.*
import std.unittest.testmacro.*

@Test
class HostArchOnLinuxTest {
    /**
     * The set names one architecture, its triple's: a build for another needs a set of its own.
     */
    @TestCase
    func isTheMachineThisProcessRunsAs() {
        // act
        let (code, out, _) = executeWithOutput("uname", ["-m"])

        // assert
        @Assert(code, 0)
        @Expect(hostArch(), String.fromUtf8(out).trimAscii())
    }
}
