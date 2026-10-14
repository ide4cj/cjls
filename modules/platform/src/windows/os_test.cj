features { os.windows }
package platform

import std.env.getVariable
import std.unittest.*
import std.unittest.testmacro.*

@Test
class HostArchOnWindowsTest {
    /**
     * The one cjls is built for on Windows: a build for another needs its own value. Windows tells a
     * process the architecture it runs as, emulated or not, in `PROCESSOR_ARCHITECTURE`.
     */
    @TestCase
    func isTheMachineThisProcessRunsAs() {
        // act, assert
        @Expect(getVariable("PROCESSOR_ARCHITECTURE"), Some("AMD64"))
        @Expect(hostArch(), "x86_64")
    }
}
