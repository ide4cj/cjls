package syntax_codegen

import std.env.{getStdErr, getStdOut}
import std.fs.Path
import std.io.OutputStream
import jian.*

@JianContext
class CommandContext {
    CommandContext(let output: CommandOutput) {}
}

/**
 * Jian resolves dependencies by type, so both output streams share one context value.
 */
struct CommandOutput {
    CommandOutput(let out: OutputStream, let err: OutputStream) {}
}

/**
 * Builds an isolated single-action CLI with generated help and usage errors.
 */
func commandApp(
    out!: OutputStream = getStdOut(),
    err!: OutputStream = getStdErr()
): JianContextApp<CommandContext> {
    JianContextApp<CommandContext>(name: "syntax_codegen", stdout: out, stderr: err)
        // The unexpanded census cannot see @JianCommand's factory overload (#176).
        .command(generateSyntax)
}

/**
 * Runs the generator CLI; usage errors return 2, generation failures return 1.
 */
main(args: Array<String>): Int64 {
    commandApp().run(args, context: CommandContext(CommandOutput(getStdOut(), getStdErr())))
}

/**
 * Generates and formats both outputs, reporting writes and handwritten accessor notes.
 */
@JianCommand[help: "Generate syntax kinds and typed tree views from a kinds file and its grammar."]
func generateSyntax(
    kindsFile!: Path = JianArgument(
        help: "Kinds file; paths in it are relative to this file.",
        preprocess: nonemptyKindsFile
    ),
    context!: CommandContext = JianFromContext<CommandContext>()
): Int64 {
    try {
        let generated = generate(kindsFile)
        for (file in generated.files) {
            writeFormatted(file.path, file.contents)
            context.output.out.write("info: wrote ${file.path}\n".toArray())
        }
        for (n in generated.model.nodes where !n.handWritten.isEmpty()) {
            context
                .output
                .out
                .write(
                    "note: ${n.name} has accessors to write by hand: ${String.join(n.handWritten, delimiter: ", ")}\n"
                        .toArray()
                )
        }
        context.output.out.flush()
        0
    } catch (e: Exception) {
        context.output.err.write("error: ${e.message}\n".toArray())
        context.output.err.flush()
        1
    }
}

/**
 * Preserves the path spelling while rejecting blank CLI inputs before filesystem access.
 *
 * @throws JianInputException - if the path is empty or contains only ASCII whitespace
 */
func nonemptyKindsFile(raw: String): String {
    if (raw.trimAscii().isEmpty()) {
        throw JianInputException("expected a kinds file")
    }
    raw
}
