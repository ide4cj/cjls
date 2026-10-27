package lsp_codegen

import std.argopt.{
    ArgumentMode,
    ArgumentParseException,
    ArgumentSpec,
    ParsedArguments,
    parseArguments
}
import std.fs.{Directory, File, Path, exists}
import fjson.fromJsonBytes

main(args: Array<String>): Int64 {
    try {
        mainImpl(args)
    } catch (e: Exception) {
        eprintln("error: ${e.message}")
        return 1
    }
}

/**
 * Generates and writes the configured protocol files; failures reach the CLI error boundary.
 */
private func mainImpl(args: Array<String>): Int64 {
    let cliArgs = parseArgs(args)
    let cfg = Config.load(cliArgs.configPath)
    let metaModel = fromJsonBytes<MetaModel>(File.readFrom(cliArgs.metaModelPath))

    let cjFiles = generateCjFiles(cfg, metaModel)
    if (!exists(cfg.outputDir)) {
        Directory.create(cfg.outputDir, recursive: true)
    }
    for (file in cjFiles) {
        File.writeTo(file.path, file.contents.toArray())
    }
    println("info: generated ${cjFiles.size} Cangjie files")

    0
}

struct CliArgs {
    CliArgs(let configPath!: Path, let metaModelPath!: Path) {}
}

/**
 * Reads the model and configuration paths.
 *
 * @throws ArgumentParseException - if required arguments are missing or blank
 */
func parseArgs(args: Array<String>): CliArgs {
    let parsed = parseArguments(args, [Full("config", r'c', RequiredValue)])

    CliArgs(
        configPath: Path(parsed.getRequiredOption("config")),
        metaModelPath: Path(parsed.getRequiredValue(parsed.nonOptions.first, "metaModel file path"))
    )
}

extend ParsedArguments {
    /**
     * @throws ArgumentParseException - if the option is missing or blank
     */
    func getRequiredOption(key: String): String {
        getRequiredValue(options.get(key), "`${key}` option")
    }

    /**
     * A blank value is refused rather than turned into `Path("")`, which throws on every join.
     *
     * @throws ArgumentParseException - if `v` is `None` or blank
     */
    func getRequiredValue(v: ?String, what: String): String {
        v
            .map { it => it.trimAscii() }
            .filter { it => !it.isEmpty() }
            .getOrThrow { => ArgumentParseException("missing required ${what}") }
    }
}
