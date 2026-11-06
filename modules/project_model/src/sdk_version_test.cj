package project_model

import std.collection.ArrayList
import std.fs.Path
import std.unittest.*
import std.unittest.testmacro.*

@Test
class SdkVersionTest {
    @TestCase
    func theVersionIsWhatCjcPrints(): Unit {
        // arrange
        let outputs =
            [
                "Cangjie Compiler: 1.3.0-alpha.20261102001050 (cjnative)\nTarget: x86_64-unknown-linux-gnu\n",
                "Cangjie Compiler: 1.0.5 (cjnative)\r\n",
                "Cangjie Compiler: 1.2.0 (cjnative)\n",
                "Cangjie Compiler: \n",
                "Cangjie Compiler: unavailable (cjnative)\n",
                "cjc: command not found\n"
            ]
        let expected: Array<?String> =
            ["1.3.0-alpha.20261102001050", "1.0.5", "1.2.0", None, None, None]

        // act
        let versions = outputs.map { output => compilerVersionOf(output) }

        // assert
        @Expect(versions, expected)
    }

    @TestCase
    func onlyExactVersionsBelongToTheWindow(): Unit {
        // arrange
        let versions =
            [
                SDK_LTS_VERSION,
                SDK_STS_VERSION,
                SDK_PIN_VERSION,
                "1.0.4",
                "1.3.0-alpha.20261002001050",
                "2.0.0"
            ]
        let expected =
            ["LTS", "STS", "pinned nightly", "out of window", "out of window", "out of window"]

        // act
        let channels = versions.map { version => sdkWindowChannel(version) }

        // assert
        @Expect(channels, expected)
    }

    @TestCase
    func readsTheSelectedCompilerAndKeepsTheSdkWhenItCannotRun(): Unit {
        // arrange
        let dir = tree([("sdk/bin/x", "")])
        let path = dir.join("sdk").toString()
        let selected = ArrayList<Path>()
        try {
            // act
            let versioned = findCangjieHome(
                path,
                env: noEnv,
                compilerOutput: {
                    cjc: Path =>
                    selected.add(cjc)
                    Some("Cangjie Compiler: 1.2.0 (cjnative)\n")
                }
            )
            let unknown = findCangjieHome(path, env: noEnv, compilerOutput: { _: Path => None })

            // assert
            @Expect(selected.size, 1)
            @Expect(selected[0].parent.parent.toString(), path)
            @Expect(versioned.flatMap { home => home.version }, Some("1.2.0"))
            @Expect(unknown.isSome())
            @Expect(unknown.flatMap { home => home.version }, None<String>)
        } finally {
            removeTree(dir)
        }
    }
}
