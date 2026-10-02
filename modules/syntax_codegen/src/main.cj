package syntax_codegen

import std.argopt.*
import std.fs.*

/**
 * `syntax_codegen <kinds file>`: writes the kinds and the typed views the kinds file and its grammar make.
 */
main(args: Array<String>): Int64 {
    let kindsFile = try {
        parseKindsFile(args)
    } catch (e: ArgumentParseException) {
        eprintln("error: ${e.message}\nusage: syntax_codegen <kinds file>")
        return 2
    }
    try {
        let generated = generate(kindsFile)
        for (file in generated.files) {
            writeFormatted(file.path, file.contents)
            println("info: wrote ${file.path}")
        }
        for (n in generated.model.nodes where !n.handWritten.isEmpty()) {
            println("note: ${n.name} has accessors to write by hand: ${String.join(n.handWritten, delimiter: ", ")}")
        }
        0
    } catch (e: Exception) {
        eprintln("error: ${e.message}")
        1
    }
}

/**
 * The kinds file `args` name, the program's name not among them: one argument, no options.
 *
 * @throws ArgumentParseException - for an option, or not exactly one argument, or a blank one
 */
func parseKindsFile(args: Array<String>): Path {
    let parsed = parseArguments(args, [])
    if (parsed.nonOptions.size != 1 || parsed.nonOptions[0].trimAscii().isEmpty()) {
        throw ArgumentParseException("takes one kinds file")
    }
    Path(parsed.nonOptions[0])
}
