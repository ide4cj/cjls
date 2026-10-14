features { os.windows }
package platform

import std.env.getVariable
import std.unittest.*
import std.unittest.testmacro.*

@Test
class HostArchOnWindowsTest {
    /**
     * The set names one architecture, its triple's: a build for another needs a set of its own. Windows
     * tells a process the architecture it runs as, emulated or not, in `PROCESSOR_ARCHITECTURE`.
     */
    @TestCase
    func isTheMachineThisProcessRunsAs() {
        // act, assert
        @Expect(getVariable("PROCESSOR_ARCHITECTURE"), Some("AMD64"))
        @Expect(hostArch(), "x86_64")
    }
}
