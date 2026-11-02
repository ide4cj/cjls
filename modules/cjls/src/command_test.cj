package cjls

import std.io.{ByteBuffer, readToEnd}
import stdx.log.NoopLogger
import fjson.{fromJsonBytes, JsonValue}
import cjls.server.settingsSchema

@Test
class CommandTest {
    @TestCase
    func helpDescribesTheDefaultActionAndTypedOptions() {
        // arrange
        let (out, err) = (ByteBuffer(), ByteBuffer())
        let app = commandApp(out: out, err: err)
        let context = CommandContext(NoopLogger())

        // act, assert
        @Expect(app.run(["--help"], context: context), 0)
        let root = written(out)
        @Expect(root.contains("Serve LSP over stdio"))
        @Expect(root.contains("--config-schema"))
        @Expect(root.contains("project"))
        @Expect(root.contains("fetch-src"))
        @Expect(app.run(["help", "fmt"], context: context), 0)
        let fmt = written(out)
        @Expect(fmt.contains("Usage: cjls fmt"))
        @Expect(fmt.contains("--check"))
        @Expect(fmt.contains("PATH"))
        @Expect(written(err), "")
    }

    @TestCase
    func invalidInputsAreUsageErrorsWithoutRunningAnAction() {
        // arrange
        let (out, err) = (ByteBuffer(), ByteBuffer())
        let app = commandApp(out: out, err: err)
        let context = CommandContext(NoopLogger())
        let invalid: Array<Array<String>> =
            [
                ["frob"],
                ["--frob"],
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

        // act, assert
        for (args in invalid) {
            @Expect(app.run(args, context: context), 2)
            @Expect(written(err).contains("Usage: cjls"))
            @Expect(written(out), "")
        }
    }

    @TestCase
    func configSchemaPrintsTheSchemaOfTheSettingsAsJson() {
        // arrange
        let out = ByteBuffer()

        // act
        let exitCode = printConfigSchema(out)

        // assert
        @Expect(exitCode, 0)
        let printed = fromJsonBytes<JsonValue>(readToEnd(out))
        @Expect(printed, settingsSchema())
    }
}
