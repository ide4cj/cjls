package lsp_codegen

import std.env.getWorkingDirectory
import std.fs.{Directory, File, exists, remove}
import std.io.{ByteBuffer, readToEnd}
import std.unittest.*
import std.unittest.testmacro.*

/**
 * Reads the complete output captured by a command test.
 */
func written(buffer: ByteBuffer): String {
    String.fromUtf8(readToEnd(buffer))
}

@Test
class LspCodegenCommandTest {
    @TestCase[args in [["--help"], ["-h"]]]
    func helpDescribesTheModelAndConfiguration(args: Array<String>) {
        // arrange
        let (out, err) = (ByteBuffer(), ByteBuffer())

        // act
        let exitCode = runCommand(args, out: out, err: err)

        // assert
        @Expect(exitCode, 0)
        let help = written(out)
        @Expect(help.contains("Usage: lsp_codegen"))
        @Expect(help.contains("META-MODEL"))
        @Expect(help.contains("--config"))
        @Expect(help.contains("-c"))
        @Expect(written(err), "")
    }

    @TestCase[args in [
        [],
        ["metaModel.json"],
        ["-c", "lsp_codegen.toml"],
        ["metaModel.json", "-c"],
        ["metaModel.json", "-c", "   "],
        ["metaModel.json", "--config="],
        ["   ", "-c", "lsp_codegen.toml"],
        ["metaModel.json", "-c", "lsp_codegen.toml", "extra.json"],
        ["metaModel.json", "-c", "lsp_codegen.toml", "--unknown"],
        ["help", "unknown"]
    ]]
    func invalidInputsAreUsageErrorsBeforeReadingFiles(args: Array<String>) {
        // arrange
        let (out, err) = (ByteBuffer(), ByteBuffer())

        // act
        let exitCode = runCommand(args, out: out, err: err)

        // assert
        @Expect(exitCode, 2)
        @Expect(written(out), "")
        @Expect(written(err).contains("Usage: lsp_codegen"))
    }

    @TestCase
    func missingFilesAreGenerationFailures() {
        // arrange
        let dir = Directory.createTemp(getWorkingDirectory())
        try {
            let (out, err) = (ByteBuffer(), ByteBuffer())
            let args =
                [dir.join("missing.json").toString(), "-c", dir.join("missing.toml").toString()]

            // act
            let exitCode = runCommand(args, out: out, err: err)

            // assert
            @Expect(exitCode, 1)
            @Expect(written(out), "")
            @Expect(written(err).startsWith("error: "))
        } finally {
            remove(dir, recursive: true)
        }
    }

    @TestCase[style in ["short", "long", "equals", "attached", "trimmed", "terminator"]]
    func theCommandReadsTheSelectedModelAndConfigAndWritesGeneratedFiles(style: String) {
        // arrange
        let dir = Directory.createTemp(getWorkingDirectory())
        try {
            let model = dir.join("model.json").toString()
            let config = dir.join("generator.toml").toString()
            File.writeTo(dir.join("cjpm.toml"), "[package]\nname = \"demo\"\n".toArray())
            File.writeTo(config, "[general]\noutput-subpackage = \"protocol\"\n".toArray())
            File.writeTo(
                model,
                #"{
                "metaData": {"version": "3.18.0"},
                "requests": [], "notifications": [], "enumerations": [], "typeAliases": [],
                "structures": [{"name": "Example", "properties": []}]
            }"#.toArray()
            )
            let args =
                match (style) {
                    case "short" => [model, "-c", config]
                    case "long" => ["--config", config, model]
                    case "equals" => [model, "--config=${config}"]
                    case "attached" => ["-c${config}", model]
                    case "terminator" => ["-c", config, "--", model]
                    case _ => ["  ${model}  ", "-c", "  ${config}  "]
                }
            let (out, err) = (ByteBuffer(), ByteBuffer())

            // act
            let exitCode = runCommand(args, out: out, err: err)

            // assert
            @Expect(exitCode, 0)
            let generated = dir.join("src").join("protocol").join("example.cj")
            @Expect(exists(generated))
            @Expect(String.fromUtf8(File.readFrom(generated)).contains("package demo.protocol"))
            @Expect(written(out).contains("info: generated"))
            @Expect(written(err), "")
        } finally {
            remove(dir, recursive: true)
        }
    }
}
