package cjls

import std.env.getWorkingDirectory
import std.fs.{Directory, File, Path, remove}
import std.io.{ByteBuffer, readToEnd}
import stdx.log.NoopLogger
import fjson.{JsonValue, fromJsonBytes}
import cjls.server.settingsSchema

@Test
class CommandTest {
    @TestCase[scenario in [
        (["--help"], "Usage: cjls", "--config-schema"),
        (["-h"], "Usage: cjls", "--config-schema"),
        (["help"], "Usage: cjls", "--config-schema"),
        (["project", "--help"], "Usage: cjls project", "--dir"),
        (["help", "project"], "Usage: cjls project", "--dir"),
        (["fmt", "-h"], "Usage: cjls fmt", "--check"),
        (["help", "fmt"], "Usage: cjls fmt", "--check"),
        (["fetch-src", "--help"], "Usage: cjls fetch-src", "--dir"),
        (["help", "fetch-src"], "Usage: cjls fetch-src", "--dir")
    ]]
    func helpDescribesTheDefaultActionAndTypedOptions(scenario: (Array<String>, String, String)) {
        // arrange
        let (args, usage, option) = scenario
        let (out, err) = (ByteBuffer(), ByteBuffer())

        // act
        let exitCode = runCommand(args, logger: NoopLogger(), out: out, err: err)
        let help = written(out)

        // assert
        @Expect(exitCode, 0)
        @Expect(help.contains(usage))
        @Expect(!help.contains("--output"))
        @Expect(!help.contains("OUTPUT"))
        @Expect(help.contains(option))
        if (usage == "Usage: cjls") {
            @Expect(help.contains("Serve LSP over stdio"))
            @Expect(help.contains("project"))
            @Expect(help.contains("fetch-src"))
        }
        if (usage == "Usage: cjls fmt") {
            @Expect(help.contains("PATH"))
        }
        @Expect(written(err), "")
    }

    @TestCase
    func invalidInputsAreUsageErrorsWithoutRunningAnAction() {
        // arrange
        let (out, err) = (ByteBuffer(), ByteBuffer())
        let invalid: Array<Array<String>> =
            [
                ["frob"],
                ["--frob"],
                ["--output", "file"],
                ["fmt", "--output", "file"],
                ["project", "sub"],
                ["project", "--frob"],
                ["project", "--dir"],
                ["project", "--dir="],
                ["fmt"],
                ["fmt", "--check"],
                ["fetch-src", "src"],
                ["fetch-src", "--dir"],
                ["fetch-src", "--dir="],
                ["fmt", "--frob", "a"],
                ["--config-schema", "x"],
                ["--config-schema", "project"],
                ["help", "frob"]
            ]

        for (args in invalid) {
            // act
            let exitCode = runCommand(args, logger: NoopLogger(), out: out, err: err)

            // assert
            @Expect(exitCode, 2)
            @Expect(written(err).contains("Usage: cjls"))
            @Expect(written(out), "")
        }
    }

    @TestCase
    func configSchemaPrintsTheSchemaOfTheSettingsAsJson() {
        // arrange
        let (out, err) = (ByteBuffer(), ByteBuffer())

        // act
        let exitCode = runCommand(["--config-schema"], logger: NoopLogger(), out: out, err: err)

        // assert
        @Expect(exitCode, 0)
        let printed = fromJsonBytes<JsonValue>(readToEnd(out))
        @Expect(printed, settingsSchema())
        @Expect(written(err), "")
    }

    @TestCase[args in [
        ["--dir", "sub"],
        ["--dir=sub"],
        ["-d", "sub"],
        ["-dsub"],
        ["--dir", "ignored", "-d", "sub"]
    ]]
    func projectResolvesDirectoryOptionsRelativeToCwd(args: Array<String>) {
        // arrange: keep cwd unchanged so concurrent tests cannot observe a different directory.
        let dir = Directory.createTemp(getWorkingDirectory())
        try {
            File.writeTo(dir.join("cjpm.toml"), "[package]\nname = \"cli_test\"\n".toArray())
            let relative = dir.fileName
            let options = args.map { arg => arg.replace("sub", relative) }
            let (out, err) = (ByteBuffer(), ByteBuffer())

            // act
            let exitCode = runCommand(
                ["project"].concat(options),
                logger: NoopLogger(),
                out: out,
                err: err
            )

            // assert
            @Expect(exitCode, 0)
            let project = fromJsonBytes<JsonValue>(readToEnd(out))
            @Expect(project["modules"][0]["name"].asString(), "cli_test")
            @Expect(written(err), "")
        } finally {
            remove(dir, recursive: true)
        }
    }

    @TestCase[check in ["--check", "-c"]]
    func fmtChecksRelativePathsBeforeAndAfterFormatting(check: String) {
        // arrange
        let dir = Directory.createTemp(getWorkingDirectory())
        try {
            let source = "func f(){let x=1}\n"
            let expected = "func f() {\n    let x = 1\n}\n"
            let files = ["a.cj", "b.cj"].map { name => dir.join(name) }
            let paths = ["a.cj", "b.cj"].map { name => Path(dir.fileName).join(name).toString() }
            for (file in files) {
                File.writeTo(file, source.toArray())
            }
            let (out, err) = (ByteBuffer(), ByteBuffer())

            // act
            let checked = runCommand(
                ["fmt", paths[0], check, paths[1]],
                logger: NoopLogger(),
                out: out,
                err: err
            )

            // assert
            @Expect(checked, 1)
            @Expect(files.map { file => String.fromUtf8(File.readFrom(file)) }, [source, source])

            // act
            let formatted = runCommand(
                ["fmt"].concat(paths),
                logger: NoopLogger(),
                out: out,
                err: err
            )

            // assert
            @Expect(formatted, 0)
            @Expect(files.map { file => String.fromUtf8(File.readFrom(file)) }, [expected, expected])

            // act
            let rechecked = runCommand(
                ["fmt", check].concat(paths),
                logger: NoopLogger(),
                out: out,
                err: err
            )

            // assert
            @Expect(rechecked, 0)
            @Expect(written(err), "")
        } finally {
            remove(dir, recursive: true)
        }
    }

    @TestCase
    func invocationStreamsCaptureCallbackCommandHelpAndUsageIndependently() {
        // Reuse application state without storing output streams in it.
        let context = CommandContext(NoopLogger())
        let (schemaOut, schemaErr) = (ByteBuffer(), ByteBuffer())
        let (helpOut, helpErr) = (ByteBuffer(), ByteBuffer())
        let (commandOut, commandErr) = (ByteBuffer(), ByteBuffer())
        let (usageOut, usageErr) = (ByteBuffer(), ByteBuffer())

        let schemaCode = CJLS_APP.run(
            ["--config-schema"],
            context: context,
            stdout: schemaOut,
            stderr: schemaErr
        )
        let schema = written(schemaOut)
        let helpCode = CJLS_APP.run(
            ["fmt", "--help"],
            context: context,
            stdout: helpOut,
            stderr: helpErr
        )
        let dir = Directory.createTemp(getWorkingDirectory())
        try {
            let commandCode = CJLS_APP.run(
                ["fmt", dir.join("missing.cj").toString()],
                context: context,
                stdout: commandOut,
                stderr: commandErr
            )
            let usageCode = CJLS_APP.run(
                ["fmt", "--output", "x"],
                context: context,
                stdout: usageOut,
                stderr: usageErr
            )

            @Expect(schemaCode, 0)
            @Expect(fromJsonBytes<JsonValue>(schema.toArray()), settingsSchema())
            @Expect(written(schemaErr), "")
            @Expect(helpCode, 0)
            let help = written(helpOut)
            @Expect(help.contains("Usage: cjls fmt"))
            @Expect(!help.contains("--output"))
            @Expect(written(helpErr), "")
            @Expect(commandCode, 1)
            @Expect(written(commandOut), "")
            @Expect(!written(commandErr).isEmpty())
            @Expect(usageCode, 2)
            @Expect(written(usageOut), "")
            @Expect(written(usageErr).contains("Usage: cjls fmt"))
            @Expect(written(schemaOut), "")
        } finally {
            remove(dir, recursive: true)
        }
    }

    @TestCase
    func repeatedInvocationsKeepCallbackAndCommandStreamsSeparate() {
        // arrange
        let (schemaOut, schemaErr) = (ByteBuffer(), ByteBuffer())
        let (commandOut, commandErr) = (ByteBuffer(), ByteBuffer())
        let dir = Directory.createTemp(getWorkingDirectory())
        try {
            // act
            let schemaCode = runCommand(
                ["--config-schema"],
                logger: NoopLogger(),
                out: schemaOut,
                err: schemaErr
            )
            let commandCode = runCommand(
                ["fmt", dir.join("missing.cj").toString()],
                logger: NoopLogger(),
                out: commandOut,
                err: commandErr
            )

            // assert
            @Expect(schemaCode, 0)
            @Expect(fromJsonBytes<JsonValue>(readToEnd(schemaOut)), settingsSchema())
            @Expect(written(schemaErr), "")
            @Expect(commandCode, 1)
            @Expect(written(commandOut), "")
            @Expect(written(commandErr).contains("missing.cj"))
        } finally {
            remove(dir, recursive: true)
        }
    }
}
