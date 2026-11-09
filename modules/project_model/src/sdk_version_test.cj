package project_model

import std.collection.ArrayList
import std.fs.{FileInfo, Path}
import std.unittest.*
import std.unittest.testmacro.*
import platform.executableFile

@Test
class SdkVersionTest {
    @TestCase[sample in [
        ("Cangjie Compiler: 1.3.0-alpha.20261102001050 (cjnative)\nTarget: x86_64-unknown-linux-gnu\n", Some("1.3.0-alpha.20261102001050")),
        ("Cangjie Compiler: 1.0.5 (cjnative)\r\n", Some("1.0.5")),
        ("Cangjie Compiler: 1.2.0 (cjnative)\n", Some("1.2.0")),
        ("Cangjie Compiler: 1.0.0 (cjnative)\r\n", Some("1.0.0")),
        ("Cangjie Compiler: \n", None),
        ("Cangjie Compiler: unavailable (cjnative)\n", None),
        ("cjc: command not found\n", None)
    ]]
    func theVersionIsWhatCjcPrints(sample: (String, ?String)): Unit {
        // arrange
        let (output, expected) = sample

        // act
        let version = compilerVersionOf(output)

        // assert
        @Expect(version, expected)
    }

    @TestCase[sample in [
        (SDK_LTS_VERSION, "LTS"),
        (SDK_STS_VERSION, "STS"),
        (SDK_PIN_VERSION, "pinned nightly"),
        ("1.0.4", "out of window"),
        ("1.3.0-alpha.20261002001050", "out of window"),
        ("2.0.0", "out of window")
    ]]
    func onlyExactVersionsBelongToTheWindow(sample: (String, String)): Unit {
        // arrange
        let (version, expected) = sample

        // act
        let channel = sdkWindowChannel(version)

        // assert
        @Expect(channel, expected)
    }

    @TestCase[sample in [
        (Some("Cangjie Compiler: 1.2.0 (cjnative)\n"), Some("1.2.0")),
        (Some("unrecognized output"), None),
        (None, None)
    ]]
    func readsOnlyTheSelectedCompilerAndKeepsTheSdk(sample: (?String, ?String)): Unit {
        // arrange
        let (output, expected) = sample
        let dir = tree([("sdk/bin/x", "")])
        let sdk = Path(dir.join("sdk").toString())
        let selected = ArrayList<Path>()
        try {
            // act
            let home = findCangjieHome(
                sdk.toString(),
                env: noEnv,
                compilerOutput: {
                    cjc =>
                    selected.add(cjc)
                    output
                }
            )

            // assert
            @Expect(selected.toArray(), [sdk.join("bin").join(executableFile("cjc"))])
            @Expect(home?.path, Some(sdk.toString()))
            @Expect(home.flatMap { selected => selected.version }, expected)
        } finally {
            removeTree(dir)
        }
    }

    @TestCase
    func aMissingCompilerKeepsTheSdkWithAnUnknownVersion(): Unit {
        // arrange
        let dir = tree([("sdk/modules/x", "")])
        let sdk = dir.join("sdk").toString()
        try {
            // act
            let home = findCangjieHome(sdk, env: noEnv)

            // assert
            @Expect(home?.path, Some(sdk))
            @Expect(home.flatMap { selected => selected.version }, None<String>)
        } finally {
            removeTree(dir)
        }
    }
}

@When[os != "Windows"]
@Test
class SdkCompilerOutputOnPosixTest {
    @TestCase[sample in [
        ("printf 'Cangjie Compiler: 1.2.0 (cjnative)\\n'", Some("1.2.0")),
        ("printf 'unrecognized output\\n'", None),
        ("printf 'Cangjie Compiler: 1.0.4 (cjnative)\\n'; exit 1", None),
        ("printf '\\377'", None)
    ]]
    func failedOrUnreadableOutputKeepsTheSdk(sample: (String, ?String)): Unit {
        // arrange: a real process exercises exit status and UTF-8 decoding without the server.
        let (body, expected) = sample
        let dir = tree([("sdk/bin/cjc", "#!/bin/sh\n${body}\n")])
        let sdk = Path(dir.join("sdk").toString())
        try {
            @Assert(FileInfo(sdk.join("bin").join("cjc")).setExecutable(true))

            // act
            let home = findCangjieHome(sdk.toString(), env: noEnv)

            // assert
            @Expect(home?.path, Some(sdk.toString()))
            @Expect(home.flatMap { selected => selected.version }, expected)
        } finally {
            removeTree(dir)
        }
    }
}
