package fbs_codegen

import std.argopt.*
import std.fs.*

/**
 * `fbs_codegen <config>`: writes the views of the schema the config names.
 */
main(args: Array<String>): Int64 {
    let config = try {
        parseConfigPath(args)
    } catch (e: ArgumentParseException) {
        eprintln("error: ${e.message}\nusage: fbs_codegen <config>")
        return 2
    }
    try {
        let file = generate(config)
        writeFormatted(file.path, file.contents)
        println("info: wrote ${file.path}")
        0
    } catch (e: Exception) {
        eprintln("error: ${e.message}")
        1
    }
}

/**
 * The config `args` name, the program's name not among them: one argument, no options.
 *
 * @throws ArgumentParseException - for an option, or not exactly one argument, or a blank one
 */
func parseConfigPath(args: Array<String>): Path {
    let parsed = parseArguments(args, [])
    if (parsed.nonOptions.size != 1 || parsed.nonOptions[0].trimAscii().isEmpty()) {
        throw ArgumentParseException("takes one config")
    }
    Path(parsed.nonOptions[0])
}
