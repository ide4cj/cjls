package fbs_codegen

import std.env.getWorkingDirectory
import std.fs.{Directory, File, Path, exists, remove}
import std.io.ByteBuffer
import std.unittest.*
import std.unittest.testmacro.*

@Test
class FbsCodegenCommandTest {
    @TestCase[args in [["--help"], ["-h"]]]
    func helpDescribesTheConfigWithoutGenerating(args: Array<String>) {
        // arrange
        let (out, err) = (ByteBuffer(), ByteBuffer())

        // act
        let exitCode = runCommand(args, out: out, err: err)
        let help = String.fromUtf8(out.bytes())

        // assert
        @Expect(exitCode, 0)
        @Expect(help.contains("Usage: fbs_codegen [OPTIONS] CONFIG"))
        @Expect(help.contains("Generation config in TOML format."))
        @Expect(help.contains("--help"))
        @Expect(String.fromUtf8(err.bytes()), "")
    }

    @TestCase[args in [[], ["a.toml", "b.toml"], [""], ["   "], ["--unknown"], ["-x", "a.toml"]]]
    func invalidArgumentsAreUsageErrors(args: Array<String>) {
        // arrange
        let (out, err) = (ByteBuffer(), ByteBuffer())

        // act
        let exitCode = runCommand(args, out: out, err: err)

        // assert
        @Expect(exitCode, 2)
        @Expect(String.fromUtf8(err.bytes()).contains("Usage: fbs_codegen"))
        @Expect(String.fromUtf8(out.bytes()), "")
    }

    @TestCase[terminator in [false, true], configName in ["config.toml", " config.toml "]]
    func aRelativeConfigGeneratesViewsWithConfigRelativePaths(
        terminator: Bool,
        configName: String
    ) {
        // arrange: leave cwd unchanged for other tests.
        let dir = Directory.createTemp(getWorkingDirectory())
        try {
            File.writeTo(
                dir.join(configName),
                "schema = 'input.fbs'\noutput = 'out/views.cj'\npackage = 'views'\n".toArray()
            )
            File.writeTo(dir.join("input.fbs"), "table T { value:int; }\nroot_type T;\n".toArray())
            let relative = Path(dir.fileName).join(configName).toString()
            let expected = generate(Path(relative))
            let args = if (terminator) { ["--", relative] } else { [relative] }
            let (out, err) = (ByteBuffer(), ByteBuffer())

            // act
            let exitCode = runCommand(args, out: out, err: err)

            // assert
            @Expect(exitCode, 0)
            @Expect(exists(dir.join("out/views.cj")))
            @Expect(String.fromUtf8(File.readFrom(expected.path)).contains("package views"))
            @Expect(String.fromUtf8(out.bytes()), "info: wrote ${expected.path}\n")
            @Expect(String.fromUtf8(err.bytes()), "")
        } finally {
            remove(dir, recursive: true)
        }
    }

    @TestCase
    func generationFailuresUseStderrAndExitOne() {
        // arrange
        let dir = Directory.createTemp(getWorkingDirectory())
        try {
            let (out, err) = (ByteBuffer(), ByteBuffer())

            // act
            let exitCode = runCommand([dir.join("missing.toml").toString()], out: out, err: err)

            // assert
            @Expect(exitCode, 1)
            @Expect(String.fromUtf8(err.bytes()).startsWith("error: "))
            @Expect(String.fromUtf8(out.bytes()), "")
        } finally {
            remove(dir, recursive: true)
        }
    }
}
