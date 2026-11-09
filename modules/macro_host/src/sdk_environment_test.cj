package macro_host

import std.env.getTempDirectory
import std.unittest.*
import std.unittest.testmacro.*
import platform.{libraryPathVariable, pathListSeparator, sdkToolEnvironment}

@Test
class NativeToolEnvironmentTest {
    @TestCase
    func nativeLoaderPathsKeepLinkerPriorityBehindTheSelectedSdk(): Unit {
        // arrange
        let root = getTempDirectory().join("cjls-native-env")
        let runtime = root.join("sdk")
        let first = root.join("first")
        let second = root.join("second")
        let inherited = root.join("inherited")
        let key = libraryPathVariable()
        let original = sdkToolEnvironment(
            [(key, inherited.toString()), ("SDKROOT", runtime.toString())],
            runtime
        )

        // act
        let environment = nativeToolEnvironment(original, runtime, [first, second])
        let paths = environment[key].split(pathListSeparator())

        // assert
        @Expect(paths[0], runtime.toString())
        @Expect(paths[1], first.toString())
        @Expect(paths[2], second.toString())
        @Expect(paths[paths.size - 1], inherited.toString())
        @Expect(!original[key].contains(first.toString()))
    }
}
