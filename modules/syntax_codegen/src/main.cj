package syntax_codegen

import std.env.{getStdErr, getStdOut}
import std.fs.Path
import std.io.OutputStream
import jian.*

let SYNTAX_CODEGEN_APP = JianApp(name: "syntax_codegen")

/**
 * Runs the generator CLI; usage errors return 2, generation failures return 1.
 */
main(args: Array<String>): Int64 {
    runCommand(args)
}

/**
 * Runs argv without the executable name; returns 2 for usage errors, 1 for generation failures.
 */
func runCommand(
    args: Array<String>,
    out!: OutputStream = getStdOut(),
    err!: OutputStream = getStdErr()
): Int64 {
    try {
        SYNTAX_CODEGEN_APP.run(args, stdout: out, stderr: err)
    } catch (e: Exception) {
        err.write("error: ${e.message}\n".toArray())
        err.flush()
        1
    }
}

/**
 * Generates and formats both outputs, reporting writes and handwritten accessor notes.
 */
@JianCommand[SYNTAX_CODEGEN_APP, root: true, help: "Generate syntax kinds and typed tree views from a kinds file and its grammar."]
func generateSyntax(
    kindsFile!: Path = JianArgument(
        help: "Kinds file; paths in it are relative to this file.",
        preprocess: nonemptyKindsFile
    ),
    output!: JianOutput = JianCurrentOutput()
): Int64 {
    let generated = generate(kindsFile)
    for (file in generated.files) {
        writeFormatted(file.path, file.contents)
        output.stdout.write("info: wrote ${file.path}\n".toArray())
    }
    for (n in generated.model.nodes where !n.handWritten.isEmpty()) {
        output
            .stdout
            .write(
                "note: ${n.name} has accessors to write by hand: ${String.join(n.handWritten, delimiter: ", ")}\n"
                    .toArray()
            )
    }
    output.stdout.flush()
    0
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
