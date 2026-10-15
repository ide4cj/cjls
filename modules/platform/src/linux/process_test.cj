features { user.platform.posix, os.linux }
package platform

import std.collection.ArrayList
import std.env.getVariable
import std.fs.Path
import std.io.InputStream
import std.unittest.*
import std.unittest.testmacro.*

@Test
class StartPipedOnLinuxTest {
    @TestCase
    func theLibraryDirectoriesComeFirstInTheirOrderBeforeThoseInherited() {
        // arrange: a child that writes the library path it got on its pipe to this process
        let inherited = getVariable("LD_LIBRARY_PATH") ?? ""

        // act
        let child = startPiped(Path("/bin/sh"), [Path("/sdk/runtime"), Path("/sdk/tools/lib")], {
            _ => ["-c", "printf %s \"$LD_LIBRARY_PATH\" >&4"]
        })
        let got = String.fromUtf8(readAll(child.fromChild))
        child.wait()

        // assert
        let expected = if (inherited.isEmpty()) {
            "/sdk/runtime:/sdk/tools/lib"
        } else {
            "/sdk/runtime:/sdk/tools/lib:${inherited}"
        }
        @Expect(got, expected)
    }
}

/**
 * What `stream` gives until its end.
 */
func readAll(stream: InputStream): Array<UInt8> {
    let all = ArrayList<UInt8>()
    let buffer = Array<UInt8>(256, repeat: 0)
    while (true) {
        let n = stream.read(buffer)
        if (n == 0) {
            return all.toArray()
        }
        all.add(all: buffer[..n])
    }
    all.toArray()
}
