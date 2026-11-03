package syntax_codegen

import std.env.getWorkingDirectory
import std.fs.{Directory, File, remove}
import std.io.ByteBuffer
import std.unittest.*
import std.unittest.testmacro.*

@Test
class SyntaxCommandTest {
    @TestCase[args in [["--help"], ["-h"]]]
    func helpDescribesTheKindsFileWithoutGenerating(args: Array<String>) {
        // arrange
        let (out, err) = (ByteBuffer(), ByteBuffer())

        // act
        let code = runCommand(args, out: out, err: err)

        // assert
        @Expect(code, 0)
        let help = String.fromUtf8(out.bytes())
        @Expect(help.contains("Usage: syntax_codegen"))
        @Expect(help.contains("KINDS-FILE"))
        @Expect(help.contains("Generate syntax kinds"))
        @Expect(err.bytes().isEmpty())
    }

    @TestCase[args in [[], ["a.toml", "b.toml"], [""], ["   "], ["--unknown"], ["-x", "a.toml"]]]
    func invalidInputsAreUsageErrors(args: Array<String>) {
        // arrange
        let (out, err) = (ByteBuffer(), ByteBuffer())

        // act
        let code = runCommand(args, out: out, err: err)

        // assert
        @Expect(code, 2)
        @Expect(out.bytes().isEmpty())
        @Expect(String.fromUtf8(err.bytes()).contains("Usage: syntax_codegen"))
    }

    @TestCase
    func missingInputFileRemainsAnOperationalError() {
        // arrange
        let dir = Directory.createTemp(getWorkingDirectory())
        try {
            let (out, err) = (ByteBuffer(), ByteBuffer())

            // act
            let code = runCommand([dir.join("missing.toml").toString()], out: out, err: err)

            // assert
            @Expect(code, 1)
            @Expect(out.bytes().isEmpty())
            @Expect(String.fromUtf8(err.bytes()).startsWith("error: "))
        } finally {
            remove(dir, recursive: true)
        }
    }

    @TestCase[terminator in [false, true], name in ["kinds.toml", " kinds.toml "]]
    func generatesBothFilesRelativeToTheKindsFile(terminator: Bool, name: String) {
        // arrange: keep cwd unchanged because the suite runs concurrently.
        let dir = Directory.createTemp(getWorkingDirectory())
        try {
            let kinds = dir.join(name)
            File.writeTo(
                kinds,
                """
                grammar = "grammar.ungram"
                kinds-output = "generated/kinds.cj"
                kinds-package = "example"
                ast-output = "generated/nodes.cj"
                ast-package = "example.ast"
                tokens = [{ name = "Int" }]
                """.toArray()
            )
            // The generator always emits the cjsyntax interfaces, so the fixture must implement each one.
            File.writeTo(
                dir.join("grammar.ungram"),
                """
                Decl = Name Modifiers? Annotation* TypeParamList? WhereClause?
                PackageHeader = Name
                Param = Name
                Name = 'Int'
                Modifiers = 'Int'
                Annotation = 'Int'
                TypeParamList = 'Int'
                WhereClause = 'Int'
                Lit = 'Int'
                """.toArray()
            )
            let (out, err) = (ByteBuffer(), ByteBuffer())
            let relative = "${dir.fileName}/${name}"
            let args = if (terminator) { ["--", relative] } else { [relative] }

            // act
            let code = runCommand(args, out: out, err: err)

            // assert
            @Expect(String.fromUtf8(err.bytes()), "")
            @Assert(code, 0)
            let kindSource = String.fromUtf8(File.readFrom(dir.join("generated/kinds.cj")))
            let astSource = String.fromUtf8(File.readFrom(dir.join("generated/nodes.cj")))
            @Expect(kindSource.contains("package example"))
            @Expect(kindSource.contains("Int"))
            @Expect(astSource.contains("package example.ast"))
            @Expect(astSource.contains("struct Lit"))
            @Expect(String.fromUtf8(out.bytes()).contains("generated/nodes.cj"))
        } finally {
            remove(dir, recursive: true)
        }
    }
}
